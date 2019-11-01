function New-PSTGViewColumnTest {
    <#
    .SYNOPSIS
        Function to create view column tests

    .DESCRIPTION
        The function will retrieve the columns for a view and create a test for it

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases to add.

    .PARAMETER View
        View(s) to create tests forr

    .PARAMETER OutputPath
        Path to output the test to

    .PARAMETER Creator
        The person that created the tests. By default the command will get the environment username

    .PARAMETER TemplateFolder
        Path to template folder. By default the internal templates folder will be used

    .PARAMETER TestClass
        Test class name to use for the test

    .PARAMETER InputObject
        Takes the parameters required from a View object that has been piped into the command

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        New-PSTGViewColumnTest -View $view -OutputPath $OutputPath

        Create a new view column test

    .EXAMPLE
        $views | New-PSTGViewColumnTest -OutputPath $OutputPath

        Create the tests using pipelines


    #>

    [CmdletBinding(SupportsShouldProcess)]

    param(
        [DbaInstanceParameter]$SqlInstance,
        [pscredential]$SqlCredential,
        [string]$Database,
        [string[]]$View,
        [string]$OutputPath,
        [string]$Creator,
        [string]$TemplateFolder,
        [string]$TestClass,
        [parameter(ParameterSetName = "InputObject", ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        # Check parameters
        if (-not $SqlInstance) {
            Stop-PSFFunction -Message "Please enter a SQL Server instance" -Target $SqlInstance
            return
        }

        if (-not $Database) {
            Stop-PSFFunction -Message "Please enter a database" -Target $Database
            return
        }

        # Check the output path
        if (-not $OutputPath) {
            Stop-PSFFunction -Message "Please enter an output path"
            return
        }

        if (-not (Test-Path -Path $OutputPath)) {
            try {
                $null = New-Item -Path $OutputPath -ItemType Directory
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the output directory" -Target $OutputPath -ErrorRecord $_
            }
        }

        # Check the template folder
        if (-not $TemplateFolder) {
            $TemplateFolder = Join-Path -Path ($script:ModuleRoot) -ChildPath "internal\templates"
        }

        if (-not (Test-Path -Path $TemplateFolder)) {
            Stop-PSFFunction -Message "Could not find template folder" -Target $OutputPath
        }

        if (-not $TestClass) {
            $TestClass = "TestBasic"
        }

        $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern

        if (-not $Creator) {
            $Creator = $env:username
        }

        # Connect to the server
        try {
            $server = Connect-DbaInstance -SqlInstance $Sqlinstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-PSFFunction -Message "Could not connect to '$Sqlinstance'" -Target $Sqlinstance -ErrorRecord $_ -Category ConnectionError
            return
        }

        # Check if the database exists
        if ($Database -notin $server.Databases.Name) {
            Stop-PSFFunction -Message "Database cannot be found on '$SqlInstance'" -Target $Database
        }

        $task = "Collecting objects"
        Write-Progress -ParentId 1 -Activity " View Columns" -Status 'Progress->' -CurrentOperation $task -Id 2
    }

    process {
        if (Test-PSFFunctionInterrupt) { return }

        if (-not $InputObject -and -not $View -and -not $SqlInstance) {
            Stop-PSFFunction -Message "You must pipe in an object or specify a View"
            return
        }

        $objects = @()

        if ($InputObject) {
            $objects += $server.Databases[$Database].Views | Where-Object Name -in $InputObject | Select-Object Schema, Name, Columns
        }
        else {
            $objects += $server.Databases[$Database].Views | Where-Object IsSystemObject -eq $false | Select-Object Schema, Name, Columns
        }

        if ($View) {
            $objects = $objects | Where-Object Name -in $View
        }

        $objectCount = $objects.Count
        $objectStep = 1

        if ($objectCount -ge 1) {
            foreach ($object in $objects) {
                $task = "Creating view $($objectStep) of $($objectCount)"
                Write-Progress -ParentId 1 -Activity "Creating..." -Status 'Progress->' -PercentComplete ($objectStep / $objectCount * 100) -CurrentOperation $task -Id 2

                $testName = "test If view $($object.Schema).$($object.Name) has the correct columns"

                # Test if the name of the test does not become too long
                if ($testName.Length -gt 128) {
                    Stop-PSFFunction -Message "Name of the test is too long" -Target $testName
                }

                $fileName = Join-Path -Path $OutputPath -ChildPath "$($testName).sql"
                $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
                $creator = $env:username

                # Import the template
                try {
                    $script = Get-Content -Path (Join-Path -Path $TemplateFolder -ChildPath "ViewColumnTest.template")
                }
                catch {
                    Stop-PSFFunction -Message "Could not import test template 'ViewColumnTest.template'" -Target $testName -ErrorRecord $_
                }

                # Get the columns
                $columns = $object.Columns

                $columnTextCollection = @()

                # Loop through the columns
                foreach ($column in $columns) {
                    $columnText = "`t('$($column.Name)', '$($column.DataType.Name)', $($column.DataType.MaximumLength), $($column.DataType.NumericPrecision), $($column.DataType.NumericScale))"
                    $columnTextCollection += $columnText
                }

                # Replace the markers with the content
                $script = $script.Replace("___TESTCLASS___", $TestClass)
                $script = $script.Replace("___TESTNAME___", $testName)
                $script = $script.Replace("___SCHEMA___", $object.Schema)
                $script = $script.Replace("___NAME___", $object.Name)
                $script = $script.Replace("___CREATOR___", $creator)
                $script = $script.Replace("___DATE___", $date)
                $script = $script.Replace("___COLUMNS___", ($columnTextCollection -join ",`n") + ";")

                # Write the test
                if ($PSCmdlet.ShouldProcess("$($object.Schema).$($object.Name)", "Writing View Column Test")) {
                    try {
                        Write-PSFMessage -Message "Creating view column test for table '$($object.Schema).$($object.Name)'"
                        $script | Out-File -FilePath $fileName

                        [PSCustomObject]@{
                            TestName = $testName
                            Category = "ViewColumn"
                            Creator  = $creator
                            FileName = $fileName
                        }
                    }
                    catch {
                        Stop-PSFFunction -Message "Something went wrong writing the test" -Target $testName -ErrorRecord $_
                    }
                }
            }
        }
    }
}