$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")

. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Database', 'OutputPath', 'TemplateFolder', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance

        if ($server.Databases.Name -notcontains $script:database) {
            $query = "CREATE DATABASE $($script:database)"
            $server.Query($query)
            $server.Refresh()
        }

        if (-not (Test-Path -Path $script:unittestfolder)) {
            $null = New-Item -Path $script:unittestfolder -ItemType Directory
        }
    }

    $result = New-PSTGDatabaseCollationTest -Database $script:database -OutputPath $script:unittestfolder -EnableException
    $file = Get-Item -Path $result.FileName

    Context "Create Database Collation Test" {

        It "Should return a result" {
            $result | Should -Not -Be $null
        }
    }

    Context "Test 1"
    It "Should have created a file" {
        $file | Should -Not -Be $null
    }

    Context "Test 2" {
        It "Result should have correct values" {
            $result.FileName | Should -Be $file.FullName
        }
    }

    AfterAll {
        #$null = Remove-DbaDatabase -SqlInstance $script:instance -Database $script:database -Confirm:$false -EnableException

        $null = Remove-Item -Path $script:unittestfolder -Recurse -Force -Confirm:$false
    }

}