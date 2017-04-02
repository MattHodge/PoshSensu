$VerbosePreference = "continue"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Function Get-NestedPSObject() {
    [PSCustomObject]$nested_object = @{
        "a_element1" = @{
            "ab_element1" = @{
                "abc_element1" = "d_leaf"
            }
        }
    }

    Return $nested_object
}

Function Get-NestedHashTable() {
    $nested_object = @{
        "h_a_element1" = @{
            "h_ab_element1" = @{
                "h_abc_element1" = "h_abcd_leaf"
            }
        }
    }

    Return $nested_object
}

Function Get-NestedPSObjectWithArrays() {
    $a_element1 = New-Object -TypeName PSObject
    $ab_element1 = New-Object -TypeName PSObject
    
    $ab_element2 = @(
        "abc2_leaf1",
        "abc2_leaf2",
        "abc2_leaf3"
    )

    $ab_element1 | Add-Member -MemberType NoteProperty -Name "abc_element1" -Value "abc1_leaf"

    $a_element1 | Add-Member -MemberType NoteProperty -Name "ab_element1" -Value $ab_element1
    $a_element1 | Add-Member -MemberType NoteProperty -Name "ab_element2" -Value $ab_element2

    $nested_object = New-Object -TypeName PSObject
    $nested_object | Add-Member -MemberType NoteProperty -Name "a_element1" -Value $a_element1

    Return $nested_object
}

Function Get-NestedPSObjectWithUnaryArrays() {
    $a_element1 = New-Object -TypeName PSObject
    $ab_element1 = New-Object -TypeName PSObject
    $ab_element2 = New-Object -TypeName PSObject
    
    $ab_element2 = @(
        "abc2_leaf1"
    )

    $ab_element1 | Add-Member -MemberType NoteProperty -Name "abc_element1" -Value "abc1_leaf"

    $a_element1 | Add-Member -MemberType NoteProperty -Name "ab_element1" -Value $ab_element1
    $a_element1 | Add-Member -MemberType NoteProperty -Name "ab_element2" -Value $ab_element2

    $nested_object = New-Object -TypeName PSObject
    $nested_object | Add-Member -MemberType NoteProperty -Name "a_element1" -Value $a_element1

    Return $nested_object
}

Function Write-PSLog {}

Describe "Merge-HashTablesAndObjects" {

    Context "when given a single nested PSObject with unary arrays" {

        It "should convert to json correctly" {
            Mock Write-PSLog { }
            
            $obj_set = Get-NestedPSObjectWithUnaryArrays
            Write-Verbose "Current context obj set:"
            Write-Verbose ($obj_set | Out-String)

            $merge_result = Merge-HashtablesAndObjects -InputObjects $obj_set
            Write-Verbose $merge_result

            $result = ConvertTo-Json -InputObject $merge_result -Depth 10 -Compress
            $result | Should Be '{"a_element1":{"ab_element1":{"abc_element1":"abc1_leaf"},"ab_element2":["abc2_leaf1"]}}'

        }
    }

    Context "When given a nested PSObject with unary arrays and a nested hashtable" {

        It "should convert to json correctly" {
            Mock Write-PSLog { }

            $obj_set1 = Get-NestedPSObjectWithUnaryArrays
            Write-Verbose "Current context obj_set1:"
            Write-Verbose ($obj_set1 | Out-String)

            $obj_set2 = Get-NestedHashTable
            Write-Verbose "Current context obj_set2:"
            Write-Verbose ($obj_set2 | Out-String)

            $merge_result = Merge-HashtablesAndObjects -InputObjects $obj_set1,$obj_set2
            # Write-Verbose $merge_result

            $result = ConvertTo-Json -InputObject $merge_result -Depth 10 -Compress
            # Write-Verbose $result
            $result | Should Be '{"a_element1":{"ab_element1":{"abc_element1":"abc1_leaf"},"ab_element2":["abc2_leaf1"]},"h_a_element1":{"h_ab_element1":{"h_abc_element1":"h_abcd_leaf"}}}'
        }
    }
}
