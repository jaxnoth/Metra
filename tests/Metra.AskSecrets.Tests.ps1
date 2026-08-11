# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.AskSecrets.Tests.ps1"
#
# Fixture strings are assembled at runtime (split prefixes) so secret scanners
# do not treat the test source as live credentials. Values are fake and unused.

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Ask secrets scrub text' {
    It 'redacts GitHub PAT' {
        InModuleScope Metra {
            $gh = ('gh' + 'p_') + ('A' * 36)
            $r = Invoke-MetraAskSecretsScrubText -Text "token $gh"
            $r.Matched | Should -BeTrue
            $r.Refuse | Should -BeFalse
            $r.Text | Should -Match '\[REDACTED:github\]'
            $r.Text | Should -Not -Match [regex]::Escape($gh)
        }
    }

    It 'redacts AWS access key id' {
        InModuleScope Metra {
            $akia = 'AKIA' + ('B' * 16)
            $r = Invoke-MetraAskSecretsScrubText -Text "key $akia"
            $r.Matched | Should -BeTrue
            $r.Text | Should -Match '\[REDACTED:aws\]'
            $r.Text | Should -Not -Match [regex]::Escape($akia)
        }
    }

    It 'redacts Slack token' {
        InModuleScope Metra {
            $xox = 'xoxb-' + ('c' * 24)
            $r = Invoke-MetraAskSecretsScrubText -Text "slack $xox"
            $r.Matched | Should -BeTrue
            $r.Text | Should -Match '\[REDACTED:slack\]'
            $r.Text | Should -Not -Match [regex]::Escape($xox)
        }
    }

    It 'redacts OpenAI-style sk- key' {
        InModuleScope Metra {
            $sk = 'sk-' + ('d' * 32)
            $r = Invoke-MetraAskSecretsScrubText -Text "openai $sk"
            $r.Matched | Should -BeTrue
            $r.Text | Should -Match '\[REDACTED:api_key\]'
            $r.Text | Should -Not -Match [regex]::Escape($sk)
        }
    }

    It 'redacts long Bearer token' {
        InModuleScope Metra {
            $tok = ('eyJ' + 'hbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9') + '.' + ('e' * 20)
            $r = Invoke-MetraAskSecretsScrubText -Text "Authorization: Bearer $tok"
            $r.Matched | Should -BeTrue
            $r.Text | Should -Match '\[REDACTED:bearer\]'
            $r.Text | Should -Not -Match [regex]::Escape($tok)
        }
    }

    It 'does not redact short Bearer placeholders' {
        InModuleScope Metra {
            foreach ($phrase in @('Bearer test', 'Bearer token', 'Bearer example')) {
                $r = Invoke-MetraAskSecretsScrubText -Text "docs say $phrase here"
                $r.Matched | Should -BeFalse
                $r.Text | Should -Match $phrase
            }
        }
    }

    It 'redacts unquoted connection password' {
        InModuleScope Metra {
            $pwd = ('Pass' + 'word=') + ('s3cret' + 'Value')
            $text = "Server=x;$pwd;Database=y"
            $r = Invoke-MetraAskSecretsScrubText -Text $text
            $r.Matched | Should -BeTrue
            $r.Text | Should -Match '\[REDACTED:connection\]'
            $r.Text | Should -Match 'Server=x;'
            $r.Text | Should -Match 'Database=y'
            $r.Text | Should -Not -Match [regex]::Escape('s3cret' + 'Value')
        }
    }

    It 'redacts double-quoted connection password' {
        InModuleScope Metra {
            $text = 'Server=x;' + ('Pass' + 'word=') + '"s3cretQuoted";Database=y'
            $r = Invoke-MetraAskSecretsScrubText -Text $text
            $r.Matched | Should -BeTrue
            $r.Text | Should -Match '\[REDACTED:connection\]'
            $r.Text | Should -Not -Match 's3cretQuoted'
        }
    }

    It 'redacts brace connection password' {
        InModuleScope Metra {
            $text = 'Server=x;' + ('Pass' + 'word=') + '{Complex Value};Database=y'
            $r = Invoke-MetraAskSecretsScrubText -Text $text
            $r.Matched | Should -BeTrue
            $r.Text | Should -Match '\[REDACTED:connection\]'
            $r.Text | Should -Not -Match 'Complex Value'
        }
    }

    It 'leaves empty Password= and Integrated Security alone' {
        InModuleScope Metra {
            $empty = 'Server=x;' + ('Pass' + 'word=') + ';Database=y'
            $integ = 'Server=x;Integrated Security=true;Database=y'
            $rEmpty = Invoke-MetraAskSecretsScrubText -Text $empty
            $rInteg = Invoke-MetraAskSecretsScrubText -Text $integ
            $rEmpty.Matched | Should -BeFalse
            $rEmpty.Text | Should -Be $empty
            $rInteg.Matched | Should -BeFalse
            $rInteg.Text | Should -Be $integ
        }
    }
}

Describe 'Ask secrets refuse PEM' {
    It 'refuses RSA private key' {
        InModuleScope Metra {
            $begin = '-----BEGIN ' + 'RSA PRIVATE KEY-----'
            $end = '-----END ' + 'RSA PRIVATE KEY-----'
            $pem = "$begin`nMIIEowIBAAKCAQEAexample`n$end"
            $r = Invoke-MetraAskSecretsScrubText -Text $pem
            $r.Refuse | Should -BeTrue
            $r.Reason | Should -Be 'pem_private_key'
            $r.Text | Should -Match '\[REDACTED:pem\]'
        }
    }

    It 'refuses EC private key' {
        InModuleScope Metra {
            $begin = '-----BEGIN ' + 'EC PRIVATE KEY-----'
            $end = '-----END ' + 'EC PRIVATE KEY-----'
            $pem = "$begin`nMHQCAQEEIQexample`n$end"
            $r = Invoke-MetraAskSecretsScrubText -Text $pem
            $r.Refuse | Should -BeTrue
            $r.Reason | Should -Be 'pem_private_key'
        }
    }

    It 'refuses OPENSSH private key' {
        InModuleScope Metra {
            $begin = '-----BEGIN ' + 'OPENSSH PRIVATE KEY-----'
            $end = '-----END ' + 'OPENSSH PRIVATE KEY-----'
            $pem = "$begin`nb3BlbnNzaC1rZXktdjEAAAA`n$end"
            $r = Invoke-MetraAskSecretsScrubText -Text $pem
            $r.Refuse | Should -BeTrue
            $r.Reason | Should -Be 'pem_private_key'
        }
    }

    It 'refuses generic PRIVATE KEY' {
        InModuleScope Metra {
            $begin = '-----BEGIN ' + 'PRIVATE KEY-----'
            $end = '-----END ' + 'PRIVATE KEY-----'
            $pem = "$begin`nMIIEvQIBADANBgkqhkiG9w0BAQEFA`n$end"
            $r = Invoke-MetraAskSecretsScrubText -Text $pem
            $r.Refuse | Should -BeTrue
            $r.Reason | Should -Be 'pem_private_key'
            $r.Notice | Should -Match 'Private-key material was blocked'
        }
    }
}

Describe 'Ask secrets object walk' {
    It 'walks nested hashtable and PSCustomObject' {
        InModuleScope Metra {
            $gh = ('gh' + 'p_') + ('F' * 36)
            $obj = [PSCustomObject]@{
                outer = @{
                    nested = [PSCustomObject]@{ token = "x $gh" }
                }
            }
            $r = Invoke-MetraAskSecretsScrubObject -InputObject $obj
            $r.Matched | Should -BeTrue
            $nested = $r.Value.outer.nested
            $tok = [string](Get-MetraProp -Object $nested -Name 'token' -Default '')
            $tok | Should -Match '\[REDACTED:github\]'
            $tok | Should -Not -Match [regex]::Escape($gh)
        }
    }

    It 'walks array of objects and preserves nulls / primitives' {
        InModuleScope Metra {
            $gh = ('gh' + 'p_') + ('G' * 36)
            $bag = @{
                items = @(
                    @{ id = 1; note = "has $gh" }
                    $null
                    42
                )
            }
            $r = Invoke-MetraAskSecretsScrubObject -InputObject $bag
            $r.Matched | Should -BeTrue
            $items = @($r.Value.items)
            $items.Count | Should -Be 3
            $null -eq $items[1] | Should -BeTrue
            $items[2] | Should -Be 42
            $note = [string]$items[0]['note']
            $note | Should -Match '\[REDACTED:github\]'
        }
    }
}

Describe 'Ask secrets notices' {
    It 'aggregates multiple kinds and collapses duplicate notices' {
        InModuleScope Metra {
            $gh = ('gh' + 'p_') + ('H' * 36)
            $tok = ('eyJ' + 'hbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9') + '.' + ('i' * 20)
            $r = Invoke-MetraAskSecretsScrubText -Text "a $gh and Bearer $tok"
            $r.Notice | Should -Match 'github'
            $r.Notice | Should -Match 'bearer'
            $joined = Join-MetraAskSecretsNotices -Notices @($r.Notice, $r.Notice, '  ')
            $joined | Should -Be $r.Notice.Trim()
        }
    }

    It 'returns null notice when no secrets' {
        InModuleScope Metra {
            $r = Invoke-MetraAskSecretsScrubText -Text 'normal routing question'
            $r.Notice | Should -BeNullOrEmpty
        }
    }

    It 'flags large redaction ratio' {
        InModuleScope Metra {
            $gh = ('gh' + 'p_') + ('J' * 80)
            $r = Invoke-MetraAskSecretsScrubText -Text $gh
            $r.RedactedCharsRatio | Should -BeGreaterThan 0.75
            $r.Notice | Should -Match 'Large amount of sensitive content removed'
        }
    }
}

Describe 'Ask secrets false-positive regression' {
    It 'does not treat ticket id, commit hash, GUID, or normal SQL as secrets' {
        InModuleScope Metra {
            $guid = [guid]::NewGuid().ToString()
            $text = @"
Ticket 1035020 on commit abcdef1 needs routing.
Correlation $guid
SELECT Id, Name FROM Users WHERE Active = 1
"@
            $r = Invoke-MetraAskSecretsScrubText -Text $text
            $r.Matched | Should -BeFalse
            $r.Refuse | Should -BeFalse
            $r.Text | Should -Be $text
        }
    }
}
