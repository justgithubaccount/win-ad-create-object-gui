# PoSHPF - Version 1.2
# Grab all resources (MahApps, etc), all XAML files, and any potential static resources
$Global:resources = Get-ChildItem -Path "$PSScriptRoot\Resources\*.dll" -ErrorAction SilentlyContinue
$Global:XAML = Get-ChildItem -Path "$PSScriptRoot\XAML\*.xaml" -ErrorAction SilentlyContinue
$Global:MediaResources = Get-ChildItem -Path "$PSScriptRoot\Media" -ErrorAction SilentlyContinue

# This class allows the synchronized hashtable to be available across threads,
# but also passes a couple of methods along with it to do GUI things via the
# object's dispatcher.
class SyncClass {
    #Hashtable containing all forms/windows and controls - automatically created when newing up
    [hashtable]$SyncHash = [hashtable]::Synchronized(@{}) 
    
    # method to close the window - pass window name
    [void]CloseWindow($windowName) { 
        $this.SyncHash.$windowName.Dispatcher.Invoke([action] { $this.SyncHash.$windowName.Close() }, "Normal") 
    }
    
    # method to update GUI - pass object name, property and value   
    [void]UpdateElement($object, $property, $value) { 
        $this.SyncHash.$object.Dispatcher.Invoke([action] { $this.SyncHash.$object.$property = $value }, "Normal") 
    } 
}
$Global:SyncClass = [SyncClass]::new() # create a new instance of this SyncClass to use.

###################
## Import Resources
###################
# Load WPF Assembly
Add-Type -assemblyName PresentationFramework

# Load Resources
foreach ($dll in $resources) { [System.Reflection.Assembly]::LoadFrom("$($dll.FullName)") | out-null }

##############
## Import XAML
##############
$xp = '[^a-zA-Z_0-9]' # All characters that are not a-Z, 0-9, or _
$vx = @()             # An array of XAML files loaded

foreach ($x in $XAML) { 
    # Items from XAML that are known to cause issues
    # when PowerShell parses them.
    $xamlToRemove = @(
        'mc:Ignorable="d"',
        "x:Class=`"(.*?)`"",
        "xmlns:local=`"(.*?)`""
    )

    $xaml = Get-Content $x.FullName # Load XAML
    $xaml = $xaml -replace "x:N", 'N' # Rename x:Name to just Name (for consumption in variables later)
    foreach ($xtr in $xamlToRemove) { $xaml = $xaml -replace $xtr } # Remove items from $xamlToRemove
    
    # Create a new variable to store the XAML as XML
    New-Variable -Name "xaml$(($x.BaseName) -replace $xp, '_')" -Value ($xaml -as [xml]) -Force
    
    # Add XAML to list of XAML documents processed
    $vx += "$(($x.BaseName) -replace $xp, '_')"
}

#######################
## Add Media Resources
#######################
$imageFileTypes = @(".jpg", ".bmp", ".gif", ".tif", ".png") # Supported image filetypes
$avFileTypes = @(".mp3", ".wav", ".wmv") # Supported audio/visual filetypes
$xp = '[^a-zA-Z_0-9]' # All characters that are not a-Z, 0-9, or _
if ($MediaResources.Count -gt 0) {
    ## Okay... the following code is just silly. I know
    ## but hear me out. Adding the nodes to the elements
    ## directly caused big issues - mainly surrounding the
    ## "x:" namespace identifiers. This is a hacky fix but
    ## it does the trick.
    foreach ($v in $vx) {
        $xml = ((Get-Variable -Name "xaml$($v)").Value) # Load the XML

        # add the resources needed for strings
        $xml.DocumentElement.SetAttribute("xmlns:sys", "clr-namespace:System;assembly=System")

        # if the document doesn't already have a "Window.Resources" create it
        if ($null -eq ($xml.DocumentElement.'Window.Resources')) { 
            $fragment = "<Window.Resources>" 
            $fragment += "<ResourceDictionary>"
        }
        
        # Add each StaticResource with the key of the base name and source to the full name
        foreach ($sr in $MediaResources) {
            $srname = "$($sr.BaseName -replace $xp, '_')$($sr.Extension.Substring(1).ToUpper())" #convert name to basename + Uppercase Extension
            if ($sr.Extension -in $imageFileTypes) { $fragment += "<BitmapImage x:Key=`"$srname`" UriSource=`"$($sr.FullName)`" />" }
            if ($sr.Extension -in $avFileTypes) { 
                $uri = [System.Uri]::new($sr.FullName)
                $fragment += "<sys:Uri x:Key=`"$srname`">$uri</sys:Uri>" 
            }    
        }

        # if the document doesn't already have a "Window.Resources" close it
        if ($null -eq ($xml.DocumentElement.'Window.Resources')) {
            $fragment += "</ResourceDictionary>"
            $fragment += "</Window.Resources>"
            $xml.DocumentElement.InnerXml = $fragment + $xml.DocumentElement.InnerXml
        }
        # otherwise just add the fragment to the existing resource dictionary
        else {
            $xml.DocumentElement.'Window.Resources'.ResourceDictionary.InnerXml += $fragment
        }

        # Reset the value of the variable
        (Get-Variable -Name "xaml$($v)").Value = $xml
    }
}

#################
## Create "Forms"
#################
$forms = @()
foreach ($x in $vx) {
    $Reader = (New-Object System.Xml.XmlNodeReader ((Get-Variable -Name "xaml$($x)").Value)) #load the xaml we created earlier into XmlNodeReader
    New-Variable -Name "form$($x)" -Value ([Windows.Markup.XamlReader]::Load($Reader)) -Force #load the xaml into XamlReader
    $forms += "form$($x)" #add the form name to our array
    $SyncClass.SyncHash.Add("form$($x)", (Get-Variable -Name "form$($x)").Value) #add the form object to our synched hashtable
}

#################################
## Create Controls (Buttons, etc)
#################################
$controls = @()
$xp = '[^a-zA-Z_0-9]' # All characters that are not a-Z, 0-9, or _
foreach ($x in $vx) {
    $xaml = (Get-Variable -Name "xaml$($x)").Value #load the xaml we created earlier
    $xaml.SelectNodes("//*[@Name]") | % { #find all nodes with a "Name" attribute
        $cname = "form$($x)Control$(($_.Name -replace $xp, '_'))"
        Set-Variable -Name "$cname" -Value $SyncClass.SyncHash."form$($x)".FindName($_.Name) #create a variale to hold the control/object
        $controls += (Get-Variable -Name "form$($x)Control$($_.Name)").Name #add the control name to our array
        $SyncClass.SyncHash.Add($cname, $SyncClass.SyncHash."form$($x)".FindName($_.Name)) #add the control directly to the hashtable
    }
}

############################
## FORMS AND CONTROLS OUTPUT
############################
Write-Host -ForegroundColor Cyan "The following forms were created:"
$forms | % { Write-Host -ForegroundColor Yellow "  `$$_" } #output all forms to screen
if ($controls.Count -gt 0) {
    Write-Host ""
    Write-Host -ForegroundColor Cyan "The following controls were created:"
    $controls | % { Write-Host -ForegroundColor Yellow "  `$$_" } #output all named controls to screen
}

#######################
## DISABLE A/V AUTOPLAY
#######################
foreach ($x in $vx) {
    $carray = @()
    $fts = $syncClass.SyncHash."form$($x)"
    foreach ($c in $fts.Content.Children) {
        if ($c.GetType().Name -eq "MediaElement") {
            #find all controls with the type MediaElement
            $c.LoadedBehavior = "Manual" #Don't autoplay
            $c.UnloadedBehavior = "Stop" #When the window closes, stop the music
            $carray += $c #add the control to an array
        }
    }
    if ($carray.Count -gt 0) {
        New-Variable -Name "form$($x)PoSHPFCleanupAudio" -Value $carray -Force # Store the controls in an array to be accessed later
        $syncClass.SyncHash."form$($x)".Add_Closed({
                foreach ($c in (Get-Variable "form$($x)PoSHPFCleanupAudio").Value) {
                    $c.Source = $null #stops any currently playing media
                }
            })
    }
}

#####################
## RUNSPACE FUNCTIONS
#####################
## Yo dawg... Runspace to clean up Runspaces
## Thank you Boe Prox / Stephen Owen
#region RSCleanup
$Script:JobCleanup = [hashtable]::Synchronized(@{}) 
$Script:Jobs = [system.collections.arraylist]::Synchronized((New-Object System.Collections.ArrayList)) #hashtable to store all these runspaces

$jobCleanup.Flag = $True #cleanup jobs
$newRunspace = [runspacefactory]::CreateRunspace() #create a new runspace for this job to cleanup jobs to live
$newRunspace.ApartmentState = "STA"
$newRunspace.ThreadOptions = "ReuseThread"
$newRunspace.Open()
$newRunspace.SessionStateProxy.SetVariable("jobCleanup", $jobCleanup) #pass the jobCleanup variable to the runspace
$newRunspace.SessionStateProxy.SetVariable("jobs", $jobs) #pass the jobs variable to the runspace
$jobCleanup.PowerShell = [PowerShell]::Create().AddScript({
        #Routine to handle completed runspaces
        Do {    
            Foreach ($runspace in $jobs) {            
                If ($runspace.Runspace.isCompleted) {
                    #if runspace is complete
                    [void]$runspace.powershell.EndInvoke($runspace.Runspace)  #then end the script
                    $runspace.powershell.dispose()                            #dispose of the memory
                    $runspace.Runspace = $null                                #additional garbage collection
                    $runspace.powershell = $null                              #additional garbage collection
                } 
            }
            #Clean out unused runspace jobs
            $temphash = $jobs.clone()
            $temphash | Where {
                $_.runspace -eq $Null
            } | ForEach {
                $jobs.remove($_)
            }        
            Start-Sleep -Seconds 1 #lets not kill the processor here 
        } while ($jobCleanup.Flag)
    })
$jobCleanup.PowerShell.Runspace = $newRunspace
$jobCleanup.Thread = $jobCleanup.PowerShell.BeginInvoke() 
#endregion RSCleanup

#This function creates a new runspace for a script block to execute
#so that you can do your long running tasks not in the UI thread.
#Also the SyncClass is passed to this runspace so you can do UI
#updates from this thread as well.
function Start-BackgroundScriptBlock($scriptBlock) {
    $newRunspace = [runspacefactory]::CreateRunspace()
    $newRunspace.ApartmentState = "STA"
    $newRunspace.ThreadOptions = "ReuseThread"          
    $newRunspace.Open()
    $newRunspace.SessionStateProxy.SetVariable("SyncClass", $SyncClass) 
    $PowerShell = [PowerShell]::Create().AddScript($scriptBlock)
    $PowerShell.Runspace = $newRunspace

    #Add it to the job list so that we can make sure it is cleaned up
    [void]$Jobs.Add(
        [pscustomobject]@{
            PowerShell = $PowerShell
            Runspace   = $PowerShell.BeginInvoke()
        }
    )
}

########################
## WIRE UP YOUR CONTROLS
########################

function PopulateComboBox {
    param(
        $ComboBox,
        [scriptblock]$QueryScript
    )

    $ComboBox.Items.Clear()
    try {
        $items = & $QueryScript
    }
    catch {
        Write-Warning "Не удалось загрузить данные AD: $($_.Exception.Message)"
        return
    }
    foreach ($item in $items) {
        [void]$ComboBox.Items.Add($item.Name)
    }
}

function LoadComboBoxAGGroup ($adGroup) {
    PopulateComboBox $formADOperatorWindowsControlManagersCmb { Get-ADGroupMember -Identity $adGroup -ErrorAction Stop | Select-Object Name }
}

function LoadComboBoxOU ($adOU) {
    PopulateComboBox $formADOperatorWindowsControlRolesCmb { Get-ADGroup -Filter * -SearchBase $adOU -ErrorAction Stop | Select-Object Name }
}

# Mapping of roles to default field values
$RoleConfig = @{
    'Администратор' = @{ Department = 'ИТ'; Title = 'Администратор' }
    'Консультант'  = @{ Department = 'Консалтинг'; Title = 'Консультант' }
    'Подрядчик'    = @{ Department = 'Подряд'; Title = 'Подрядчик' }
    'Сотрудник'    = @{ Department = 'Сотрудники'; Title = 'Сотрудник' }
    'Аудитор'      = @{ Department = 'Аудит'; Title = 'Аудитор' }
}

function ViewADUser {
    $preview = @(
        "Имя: $($formADOperatorWindowsControlDisplayNameTxt.Text)"
        "Логин: $($formADOperatorWindowsControlSamAccountNameTxt.Text)"
        "Компания: $($formADOperatorWindowsControlCompanyTxt.Text)"
        "Отдел: $($formADOperatorWindowsControlDepartmentTxt.Text)"
        "Должность: $($formADOperatorWindowsControlTitleTxt.Text)"
        "Email: $($formADOperatorWindowsControlMailTxt.Text)"
        "Телефон: $($formADOperatorWindowsControlTelephoneNumberTxt.Text)"
        "Описание: $($formADOperatorWindowsControlDescriptionTxt.Text)"
        "Область: $($formADOperatorWindowsControlStTxt.Text)"
        "Город: $($formADOperatorWindowsControlLocationTxt.Text)"
        "Комната: $($formADOperatorWindowsControlPhysicalDeliveryOfficeNameTxt.Text)"
        ''
        'Страна, ролевая группа и руководитель пока не сохраняются в AD.'
    ) -join [Environment]::NewLine
    [void][System.Windows.MessageBox]::Show($preview, 'Предварительный просмотр')
}

function SetDisplayName {
    $firstName = $formADOperatorWindowsControlGivenNameTxt.Text.Trim()
    $lastName = $formADOperatorWindowsControlSurnameTxt.Text.Trim()

    $dispayNameStatic = $lastName + " " + $firstName
    $formADOperatorWindowsControlDisplayNameTxt.Text = $dispayNameStatic.Trim()
}

function SetLoginName {
    $firstName = $formADOperatorWindowsControlGivenNameTxt.Text.Trim()
    $lastName = $formADOperatorWindowsControlSurnameTxt.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($firstName) -or [string]::IsNullOrWhiteSpace($lastName)) {
        return ''
    }

    # Получим первую букву имени
    $firstLetterName = $firstName.SubString(0, 1)
    $loginName = $firstLetterName + $lastName

    return Convert2Latin($loginName.ToLower())
}

function Convert2Latin($inString) {

    # Обрезаем пустые пробелы по краям
    $inString = $inString.Trim()
    
    # Определяем таблицу соответствия
    $char_ru = "а", "А", "б", "Б", "в", "В", "г", "Г", "д", "Д", "е", "Е", "ё", "Ё", "ж", "Ж", "з", "З", "и", "И", "й", "Й", "к", "К", "л", "Л", "м", "М", "н", "Н", "о", "О", "п", "П", "р", "Р", "с", "С", "т", "Т", "у", "У", "ф", "Ф", "х", "Х", "ц", "Ц", "ч", "Ч", "ш", "Ш", "щ", "Щ", "ъ", "Ъ", "ы", "Ы", "ь", "Ь", "э", "Э", "ю", "Ю", "я", "Я"
    $char_en = "a", "A", "b", "B", "v", "V", "g", "G", "d", "D", "e", "E", "e", "E", "zh", "Zh", "z", "Z", "i", "I", "y", "Iy", "k", "K", "l", "L", "m", "M", "n", "N", "o", "O", "p", "P", "r", "R", "s", "S", "t", "T", "u", "U", "f", "F", "kh", "Kh", "ts", "Ts", "ch", "Ch", "sh", "Sh", "sch", "Sch", "", "", "y", "Y", "", "", "e", "E", "yu", "Yu", "ya", "Ya"
    $TempString = ""
    
    # Перебираем слово по буквам
    for ($i = 0; $i -lt $inString.Length; $i++) { 
        $t = [array]::IndexOf($char_ru, [string]$inString[$i])
        if ($t -ge 0) {
            $TempString += $char_en[$t]
        }
        else {
            $TempString += $inString[$i]
        }
    }
    
    return $TempString
}

# Функция создания пользователя
function CreateADUser ($upnSuffix, $pathOU) {
    $accountName = $formADOperatorWindowsControlSamAccountNameTxt.Text.Trim()
    $displayName = $formADOperatorWindowsControlDisplayNameTxt.Text.Trim()
    $givenName = $formADOperatorWindowsControlGivenNameTxt.Text.Trim()
    $surname = $formADOperatorWindowsControlSurnameTxt.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($accountName) -or [string]::IsNullOrWhiteSpace($givenName) -or
        [string]::IsNullOrWhiteSpace($surname) -or $formADOperatorWindowsControlPasswordTxt.SecurePassword.Length -eq 0) {
        [void][System.Windows.MessageBox]::Show('Заполните имя, фамилию, логин и пароль.', 'Недостаточно данных')
        return
    }
    $upn = $accountName + $upnSuffix

    $user = @{
        Name              = $displayName
        DisplayName       = $displayName
        GivenName         = $givenName
        Surname           = $surname
        UserPrincipalName = $upn
        SamAccountName    = $accountName
        Path              = $pathOU
        AccountPassword   = $formADOperatorWindowsControlPasswordTxt.SecurePassword
        Enabled           = $true
        ErrorAction       = 'Stop'
    }
    $optionalFields = @{
        Company      = $formADOperatorWindowsControlCompanyTxt.Text
        Department   = $formADOperatorWindowsControlDepartmentTxt.Text
        Title        = $formADOperatorWindowsControlTitleTxt.Text
        EmailAddress = $formADOperatorWindowsControlMailTxt.Text
        OfficePhone  = $formADOperatorWindowsControlTelephoneNumberTxt.Text
        Description  = $formADOperatorWindowsControlDescriptionTxt.Text
        State        = $formADOperatorWindowsControlStTxt.Text
        City         = $formADOperatorWindowsControlLocationTxt.Text
        Office       = $formADOperatorWindowsControlPhysicalDeliveryOfficeNameTxt.Text
    }
    foreach ($field in $optionalFields.Keys) {
        if (-not [string]::IsNullOrWhiteSpace($optionalFields[$field])) {
            $user[$field] = $optionalFields[$field].Trim()
        }
    }

    try {
        New-ADUser @user
        [void][System.Windows.MessageBox]::Show("Пользователь $accountName создан.", 'Готово')
    }
    catch {
        [void][System.Windows.MessageBox]::Show($_.Exception.Message, 'Ошибка создания пользователя')
    }
}

####################
###### Events ######
####################

$formADOperatorWindowsControlSetLoginNameBtn.Add_Click({
        $formADOperatorWindowsControlSamAccountNameTxt.Clear()
        $formADOperatorWindowsControlSamAccountNameTxt.Text = SetLoginName
    })

$formADOperatorWindowsControlPreCreateBtn.Add_Click({
        ViewADUser
    })

$formADOperatorWindowsControlCreateBtn.Add_Click({
        CreateADUser "@rsvet.ru" "OU=Staging Users,DC=rsvet,DC=ru"
    })

$formADOperatorWindowsControlGivenNameTxt.Add_TextChanged({
        SetDisplayName
    })

$formADOperatorWindowsControlSurnameTxt.Add_TextChanged({
        SetDisplayName
    })

$formADOperatorWindowsControlTypeAccCbm.Add_SelectionChanged({
        $selectedType = $formADOperatorWindowsControlTypeAccCbm.SelectedItem
        if ($null -ne $selectedType -and $RoleConfig.ContainsKey($selectedType)) {
            $config = $RoleConfig[$selectedType]
            if ($config.Department) {
                $formADOperatorWindowsControlDepartmentTxt.Text = $config.Department
            }
            if ($config.Title) {
                $formADOperatorWindowsControlTitleTxt.Text = $config.Title
            }
        }
    })

############################
###### DISPLAY DIALOG ######
############################

$formADOperatorWindows.Add_ContentRendered({
        LoadComboBoxAGGroup "PosDirector"
        LoadComboBoxOU "OU=User,OU=Roles,OU=Groups,OU=Assn,DC=rsvet,DC=ru"

        # Типы пользователей
        $formADOperatorWindowsControlTypeAccCbm.Items.Add("Администратор")
        $formADOperatorWindowsControlTypeAccCbm.Items.Add("Консультант")
        $formADOperatorWindowsControlTypeAccCbm.Items.Add("Подрядчик")
        $formADOperatorWindowsControlTypeAccCbm.Items.Add("Сотрудник")
        $formADOperatorWindowsControlTypeAccCbm.Items.Add("Аудитор")

    })

[void]$formADOperatorWindows.ShowDialog()

##########################
##### SCRIPT CLEANUP #####
##########################

$jobCleanup.Flag = $false #Stop Cleaning Jobs
$jobCleanup.PowerShell.Runspace.Close() #Close the runspace
$jobCleanup.PowerShell.Dispose() #Remove the runspace from memory
