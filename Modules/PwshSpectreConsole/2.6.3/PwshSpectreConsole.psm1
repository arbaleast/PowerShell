using namespace System.Management.Automation
using namespace Spectre.Console
using namespace Spectre.Console.Rendering
using namespace PwshSpectreConsole
#region PwshSpectreConsole/private/completions/Completers.psm1


class ArgumentCompletionsSpectreColors : ArgumentCompleterAttribute {
    ArgumentCompletionsSpectreColors() : base({
            param(
                [string] $commandName,
                [string] $parameterName,
                [string] $wordToComplete,
                [Language.CommandAst] $commandAst,
                [System.Collections.IDictionary] $fakeBoundParameters
            )
            foreach ($Color in ([Spectre.Console.Color] | Get-Member -Static -Type Properties).Name) {
                if ($Color -like "$wordToComplete*") {
                    [CompletionResult]::new(
                        <# completionText #> $Color,
                        <# listItemText #>   ([Spectre.Console.Markup]::new($Color, [Spectre.Console.Style]::new([Spectre.Console.Color]::$Color)) | Out-SpectreHost),
                        <# resultType #>     'ParameterValue',
                        <# toolTip #>        $Color
                    )
                }
            }
        }) { }
}

class SpectreConsoleTableBorder : IValidateSetValuesGenerator {
    [String[]] GetValidValues() {
        $lookup = [Spectre.Console.TableBorder] | Get-Member -Static -MemberType Properties | Select-Object -ExpandProperty Name
        return $lookup
    }
}

class SpectreConsoleBoxBorder : IValidateSetValuesGenerator {
    [String[]] GetValidValues() {
        $lookup = [Spectre.Console.BoxBorder] | Get-Member -Static -MemberType Properties | Select-Object -ExpandProperty Name
        return $lookup
    }
}

class SpectreConsoleJustify : IValidateSetValuesGenerator {
    [String[]] GetValidValues() {
        $lookup = [Spectre.Console.Justify].GetEnumNames()
        return $lookup
    }
}

class SpectreConsoleHorizontalAlignment : IValidateSetValuesGenerator {
    [String[]] GetValidValues() {
        $lookup = [Spectre.Console.HorizontalAlignment].GetEnumNames()
        return $lookup
    }
}

class SpectreConsoleVerticalAlignment : IValidateSetValuesGenerator {
    [String[]] GetValidValues() {
        $lookup = [Spectre.Console.VerticalAlignment].GetEnumNames()
        return $lookup
    }
}

class SpectreConsoleSpinner : IValidateSetValuesGenerator {
    [String[]] GetValidValues() {
        $lookup = [Spectre.Console.Spinner+Known] | Get-Member -Static -MemberType Properties | Select-Object -ExpandProperty Name
        return $lookup
    }
}

class SpectreConsoleTreeGuide : IValidateSetValuesGenerator {
    [String[]] GetValidValues() {
        $lookup = [Spectre.Console.TreeGuide] | Get-Member -Static -MemberType Properties | Select-Object -ExpandProperty Name
        return $lookup
    }
}

class SpectreConsoleExceptionFormats : IValidateSetValuesGenerator {
    [String[]] GetValidValues() {
        $lookup = [Spectre.Console.ExceptionFormats] | Get-Member -Static -MemberType Properties | Select-Object -ExpandProperty Name
        return $lookup
    }
}


#endregion


#region PwshSpectreConsole/private/completions/Transformers.psm1


class ColorTransformationAttribute : ArgumentTransformationAttribute {

    static [object] TransformItem([object]$inputData) {
        if ($InputData -is [Spectre.Console.Color]) {
            return $InputData
        }
        if ($InputData.StartsWith('#')) {
            $hexBytes = [System.Convert]::FromHexString($InputData.Substring(1))
            return [Spectre.Console.Color]::new($hexBytes[0], $hexBytes[1], $hexBytes[2])
        }
        if ($InputData -is [String]) {
            return [Spectre.Console.Color]::$InputData
        }
        throw [System.ArgumentException]::new("Cannot convert $($inputData.GetType().FullName) '$InputData' to [Spectre.Console.Color]")
    }

    [object] Transform([EngineIntrinsics]$engine, [object]$inputData) {
        return [ColorTransformationAttribute]::TransformItem($inputData)
    }
}

class StyleTransformationAttribute : ArgumentTransformationAttribute {

    static [object] TransformItem([object]$inputData) {
        if ($InputData -is [Spectre.Console.Style]) {
            return $InputData
        }
        if ($InputData -is [Spectre.Console.Color]) {
            return [Spectre.Console.Style]::new($InputData)
        }
        if ($InputData -is [String]) {
            return [Spectre.Console.Style]::Parse($InputData)
        }
        throw [System.ArgumentException]::new("Cannot convert $($inputData.GetType().FullName) '$InputData' to [Spectre.Console.Style]")
    }

    [object] Transform([EngineIntrinsics]$engine, [object]$inputData) {
        return [StyleTransformationAttribute]::TransformItem($inputData)
    }
}

class TreeItemTransformationAttribute : ArgumentTransformationAttribute {

    static[object] TransformItem([object] $TreeItem) {
        $TransformedTreeItem = @{}

        if ($TreeItem -isnot [hashtable]) {
            throw "Input for Spectre Tree must be a hashtable with 'Value' (and the optional 'Children') keys"
        }

        if ($TreeItem.Keys -notcontains "Value" -and $TreeItem.Keys -notcontains "Label") {
            throw "Input for Spectre Tree must be a hashtable with 'Value' (and the optional 'Children') keys"
        }

        if ($TreeItem.Keys -contains "Value") {
            $TransformedTreeItem["Value"] = $TreeItem.Value
        } else {
            $TransformedTreeItem["Value"] = $TreeItem.Label
        }

        if ($null -eq $TransformedTreeItem["Value"]) {
            throw "Spectre tree value cannot be null"
        }

        $TransformedTreeItem["Children"] = @()

        if ($TreeItem.Keys -contains "Children") {
            if ($TreeItem.Children -isnot [array]) {
                throw "Children must be an array of tree items (hashtables with 'Value' and 'Children' keys)"
            }
            foreach ($child in $TreeItem.Children) {
                $TransformedTreeItem["Children"] += [TreeItemTransformationAttribute]::TransformItem($child)
            }
        }

        return $TransformedTreeItem
    }

    [object] Transform([EngineIntrinsics]$engine, [object]$inputData) {
        return [TreeItemTransformationAttribute]::TransformItem($inputData)
    }
}

class ColorThemeTransformationAttribute : ArgumentTransformationAttribute {
    [object] Transform([EngineIntrinsics]$engine, [object]$inputData) {
        if ($inputData -isnot [hashtable]) {
            throw "Color theme must be a hashtable of Spectre Console color names and values"
        }
        $outputData = @{}
        foreach ($color in $inputData.GetEnumerator()) {
            $styleValue = [StyleTransformationAttribute]::TransformItem($color.Value)
            $outputData[$color.Key] = $styleValue
        }
        return $outputData
    }
}

class RenderableTransformationAttribute : ArgumentTransformationAttribute {
    [object] Transform([EngineIntrinsics]$engine, [object]$inputData) {
        # Converting data from a Format-* cmdlet to a Spectre Console object is not supported as it's already formatted for console output by the default host
        if ($InputData.GetType().FullName -like "*Internal.Format*") {
            throw "Cannot convert PowerShell Format data to be Spectre Console compatible. This object has likely already been formatted with a Format-* cmdlet."
        }

        # These objects are already renderable
        if ($InputData -is [Spectre.Console.Rendering.Renderable]) {
            return $InputData
        }

        # Some stuff isn't a direct descendant of Renderable but can be rendered
        if ($InputData.GetType().GetInterfaces() | Select-Object -ExpandProperty Name | Where-Object { $_ -eq "IRenderable" }) {
            return $InputData
        }

        # For others just dump them as either strings formatted with markup which are easy to identify by the closing tag [/] or as plain text
        if ($InputData -like "*[/]*" -or $InputData -like "*:*:*") {
            try {
                $markup = [Spectre.Console.Markup]::new($InputData)
                return $markup
            } catch {
                throw @(
                    "`n`nYour input includes Spectre Console markup characters (see https://spectreconsole.net/markup).",
                    "Escape the special characters in the input before using it in a Spectre Console function using the Get-SpectreEscapedText function.",
                    "",
                    "  e.g. `$myEscapedInput = Get-SpectreEscapedText '$InputData'",
                    "`n"
                ) -join "`n"
            }
        } else {
            return [Spectre.Console.Text]::new(($InputData | Out-String -NoNewline))
        }
    }
}

class ChartItemTransformationAttribute : ArgumentTransformationAttribute {

    static [object] TransformItem([object]$inputData) {
        # These objects are already renderable
        if ($InputData -is [SpectreChartItem]) {
            return $InputData
        }

        if ($inputData -is [hashtable]) {
            if ($inputData.Keys -contains "Label" -and $inputData.Keys -contains "Value" -and $inputData.Keys -contains "Color") {
                return [SpectreChartItem]::new($inputData.Label, $inputData.Value, $inputData.Color)
            }
            throw "Hashtable must contain 'Label', 'Value', and 'Color' keys to be converted to a [SpectreChartItem]"
        }

        if ($inputData -is [PSCustomObject]) {
            if ($inputData.PSObject.Properties.Name -contains "Label" -and $inputData.PSObject.Properties.Name -contains "Value" -and $inputData.PSObject.Properties.Name -contains "Color") {
                return [SpectreChartItem]::new($inputData.Label, $inputData.Value, $inputData.Color)
            }
            throw "PSCustomObject must contain 'Label', 'Value', and 'Color' properties to be converted to a [SpectreChartItem]"
        }

        throw "Cannot convert $($inputData.GetType().FullName) to [SpectreChartItem]. Expected a hashtable or PSCustomObject with 'Label', 'Value', and 'Color' properties."
    }

    [object] Transform([EngineIntrinsics]$engine, [object]$inputData) {
        $outputData = @()
        foreach ($dataItem in $inputData) {
            $outputData += [ChartItemTransformationAttribute]::TransformItem($dataItem)
        }
        return $outputData
    }
}

class GridRowTransformationAttribute : ArgumentTransformationAttribute {

    static [object] TransformItem([object]$inputData) {
        # These objects are already renderable
        if ($InputData -is [SpectreGridRow]) {
            return $InputData
        }

        return [SpectreGridRow]::new($inputData)
    }

    [object] Transform([EngineIntrinsics]$engine, [object]$inputData) {
        $outputData = @()
        foreach ($dataItem in $inputData) {
            $outputData += [GridRowTransformationAttribute]::TransformItem($dataItem)
        }
        return $outputData
    }
}


#endregion


#region PwshSpectreConsole/private/models/SpectreChartItem.psm1


class SpectreChartItem {
    [string] $Label
    [double] $Value
    [Spectre.Console.Color] $Color

    SpectreChartItem([string] $Label, [double] $Value, [Spectre.Console.Color] $Color) {
        $this.Label = $Label
        $this.Value = $Value
        $this.Color = $Color
    }
}


#endregion


#region PwshSpectreConsole/private/models/SpectreGridRow.psm1


class SpectreGridRow {

    hidden [Spectre.Console.Rendering.Renderable[]] $InternalColumns = @()

    [int] Count() {
        return $this.InternalColumns.Count
    }

    [Spectre.Console.GridRow] ToGridRow() {
        return [Spectre.Console.GridRow]::new([Spectre.Console.Rendering.Renderable[]]$this.InternalColumns)
    }

    SpectreGridRow([object[]] $Columns) {
        foreach ($column in $Columns) {
            if ($column -is [Spectre.Console.Rendering.Renderable]) {
                $this.InternalColumns += $column
            } elseif ($column -like "*[/]*") {
                $this.InternalColumns += [Spectre.Console.Markup]::new($column)
            } else {
                $this.InternalColumns += [Spectre.Console.Text]::new($column.ToString().TrimEnd())
            }
        }
    }
}


#endregion


#region PwshSpectreConsole/private/colors/Convert-HslToRgb.ps1


function Convert-HslToRgb {
    param(
        [ValidateRange(0, 360)]
        [int] $Hue,
        [ValidateRange(0, 100)]
        [int] $Saturation,
        [ValidateRange(0, 100)]
        [int] $Lightness
    )

    $huePercent = $Hue / 360.0
    $saturationPercent = $Saturation / 100.0
    $lightnessPercent = $Lightness / 100.0

    if ($saturationPercent -eq 0) {
        $red = $lightnessPercent
        $green = $lightnessPercent
        $blue = $lightnessPercent
    } else {
        $q = if ($lightnessPercent -lt 0.5) {
            $lightnessPercent * (1 + $saturationPercent)
        } else {
            $lightnessPercent + $saturationPercent - ($lightnessPercent * $saturationPercent)
        }
        $p = 2 * $lightnessPercent - $q

        $red = Convert-PqtToRgb -P $p -Q $q -T ($huePercent + (1 / 3))
        $green = Convert-PqtToRgb -P $p -Q $q -T $huePercent
        $blue = Convert-PqtToRgb -P $p -Q $q -T ($huePercent - (1 / 3))
    }

    return @(
        [int]($red * 255),
        [int]($green * 255),
        [int]($blue * 255)
    )
}


#endregion


#region PwshSpectreConsole/private/colors/Convert-PqtToRgb.ps1


function Convert-PqtToRgb {
    param(
        [double] $P,
        [double] $Q,
        [double] $T
    )

    if ($T -lt 0) {
        $T += 1
    }
    if ($T -gt 1) {
        $T -= 1
    }

    if ($T -lt (1 / 6)) {
        return $P + ($Q - $P) * 6 * $T
    }
    if ($T -lt (1 / 2)) {
        return $Q
    }
    if ($T -lt (2 / 3)) {
        return $P + ($Q - $P) * (2 / 3 - $T) * 6
    }

    return $P
}


#endregion


#region PwshSpectreConsole/private/colors/Convert-RgbToHsv.ps1


function Convert-RgbToHsv {
    param(
        [int] $Red,
        [int] $Green,
        [int] $Blue
    )

    $redPercent = $Red / 255.0
    $greenPercent = $Green / 255.0
    $bluePercent = $Blue / 255.0

    $max = [Math]::Max([Math]::Max($redPercent, $greenPercent), $bluePercent)
    $min = [Math]::Min([Math]::Min($redPercent, $greenPercent), $bluePercent)
    $delta = $max - $min

    $hue = 0
    $saturation = 0
    $value = 0

    if ($delta -eq 0) {
        $hue = 0
    } elseif ($max -eq $redPercent) {
        $hue = 60 * ((($greenPercent - $bluePercent) / $delta) % 6)
    } elseif ($max -eq $greenPercent) {
        $hue = 60 * ((($bluePercent - $redPercent) / $delta) + 2)
    } elseif ($max -eq $bluePercent) {
        $hue = 60 * ((($redPercent - $greenPercent) / $delta) + 4)
    }

    if ($hue -lt 0) {
        $hue = 360 + $hue
    }

    if ($max -eq 0) {
        $saturation = 0
    } else {
        $saturation = $delta / $max * 100
    }

    $value = $max * 100

    return @(
        [int]$hue,
        [int]$saturation,
        [int]$value
    )
}


#endregion


#region PwshSpectreConsole/private/colors/Get-ColorCategory.ps1


function Get-ColorCategory {
    param (
        [int] $Hue,
        [int] $Saturation,
        [int] $Value
    )

    $categories = @{
        "02 Red" = @(0..20 + 350..360)
        "03 Orange" = @(21..45)
        "04 Yellow" = @(46..60)
        "05 Green" = @(61..108)
        "06 Green2" = @(109..150)
        "07 Cyan" = @(151..190)
        "08 Blue" = @(191..220)
        "09 Blue2" = @(221..240)
        "10 Purple" = @(241..280)
        "11 Pink1" = @(281..300)
        "12 Pink" = @(301..350)
    }

    if ($Saturation -lt 15) {
        if ($Value -lt 40) {
            return "00 Grey"
        }
        return "00 GreyZMud"
    }

    foreach ($category in $categories.GetEnumerator()) {
        if ($Hue -in $category.Value) {
            $cat = $category.Key
            if ($Saturation -lt 2) {
                $cat = $cat + "ZMud"
            }
            return $cat
        }
    }
}


#endregion


#region PwshSpectreConsole/private/colors/Get-ColorLightness.ps1


function Get-ColorLightness {
    param(
        [int] $Red,
        [int] $Green,
        [int] $Blue
    )

    $redPercent = $Red / 255.0
    $greenPercent = $Green / 255.0
    $bluePercent = $Blue / 255.0

    $max = [Math]::Max([Math]::Max($redPercent, $greenPercent), $bluePercent)
    $min = [Math]::Min([Math]::Min($redPercent, $greenPercent), $bluePercent)
    
    return ($max + $min) / 2
}


#endregion


#region PwshSpectreConsole/private/embedded/PwshSyntaxHighlight.ps1


$script:Themes = @{
    Github = @{
        Function      = @{ R = 255; G = 123; B = 114 }
        Generic       = @{ R = 199; G = 159; B = 252 }
        String        = @{ R = 143; G = 185; B = 221 }
        Variable      = @{ R = 255; G = 255; B = 255 }
        Identifier    = @{ R = 110; G = 174; B = 231 }
        Number        = @{ R = 255; G = 255; B = 255 }
        Keyword       = @{ R = 255; G = 123; B = 114 }
        Default       = @{ R = 200; G = 200; B = 200 }
        ForegroundRgb = @{ R = 102; G = 102; B = 102 }
        BackgroundRgb = @{ R = 35; G = 35; B = 35 }
        HighlightRgb  = @{ R = 231; G = 72; B = 86 }
    }
    Matrix = @{
        Function      = @{ R = 255; G = 255; B = 255 }
        Generic       = @{ R = 113; G = 255; B = 96 }
        String        = @{ R = 202; G = 255; B = 194 }
        Variable      = @{ R = 200; G = 255; B = 200 }
        Identifier    = @{ R = 131; G = 193; B = 26 }
        Number        = @{ R = 255; G = 255; B = 255 }
        Keyword       = @{ R = 40; G = 220; B = 20 }
        Default       = @{ R = 0; G = 120; B = 0 }
        ForegroundRgb = @{ R = 102; G = 190; B = 102 }
        BackgroundRgb = @{ R = 15; G = 45; B = 15 }
        HighlightRgb  = @{ R = 255; G = 221; B = 0 }
    }
}

function Write-CodeblockHeader {
    param (
        [string] $Language = "pwsh"
    )
    Write-Host -ForegroundColor DarkGray ((" " * ($Host.UI.RawUI.WindowSize.Width - $Language.Length)) + $Language)
}

function Write-Codeblock {
    <#
        .SYNOPSIS
            Writes a code block to the host.
            Intended for internal use only when you want to show a code block with some nicer formatting.

        .DESCRIPTION
            The Write-Codeblock function outputs a code block to the host console with optional line numbers,
            syntax highlighting, and line or extent highlighting. The function also supports custom foreground
            and background colors.

        .NOTES
            Author: Shaun Lawrie
            This was originally going to be using a screenbuffer but I wanted to support really long functions that may scroll the
            terminal so this streams the lines out from top to bottom which isn't the fastest way to render but it was the most
            reliable way I found to avoid mangling the code as it was being written out.
    #>
    param (
        # The text containing the code to write to the host
        [Parameter(ValueFromPipeline = $true, Mandatory)]
        [string] $Text,
        # Show a gutter with line numbers
        [switch] $ShowLineNumbers,
        # Syntax highlight the code block
        [switch] $SyntaxHighlight,
        # Extents to highlight in the code block
        [array] $HighlightExtents,
        # Lines to highlight in the code block
        [array] $HighlightLines,
        # The theme to use to render the code
        [ValidateSet("Github", "Matrix")]
        [string] $Theme = "Github"
    )

    $ForegroundRgb = $script:Themes[$Theme].ForegroundRgb
    $BackgroundRgb = $script:Themes[$Theme].BackgroundRgb

    # Work out the width of the console minus the line-number gutter
    $gutterSize = 0
    if ($ShowLineNumbers) {
        $gutterSize = $Text.Split("`n").Count.ToString().Length + 1
    }
    $codeWidth = $Host.UI.RawUI.WindowSize.Width - $gutterSize

    try {
        [Console]::CursorVisible = $false
        
        $functionLineNumber = 1
        $resetEscapeCode = "$([Char]27)[0m"
        $foregroundColorEscapeCode = "$([Char]27)[38;2;{0};{1};{2}m" -f $ForegroundRgb.R, $ForegroundRgb.G, $ForegroundRgb.B
        $backgroundColorEscapeCode = "$([Char]27)[48;2;{0};{1};{2}m" -f $BackgroundRgb.R, $BackgroundRgb.G, $BackgroundRgb.B

        # Get all code tokens
        $tokens = @()
        [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$null) | Out-Null
        $lineTokens = Expand-Tokens -Tokens $tokens | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Text) } | Group-Object { $_.Extent.StartLineNumber }
        $lineExtents = $HighlightExtents | Group-Object { $_.StartLineNumber }

        $functionLinesToRender = $Text.Split("`n")
        foreach ($line in $functionLinesToRender) {
            $gutterText = ""
            if ($ShowLineNumbers) {
                $gutterText = $functionLineNumber.ToString().PadLeft($gutterSize - 1) + " "
            }

            # Disable syntax highlighting for specifically highlighted lines
            $lineSyntax = $SyntaxHighlight
            $lineHighlight = $false
            if ($HighlightLines -contains $functionLineNumber) {
                $lineSyntax = $false
                $lineHighlight = $true
            }

            # Work out the lines that will be wrapped in the terminal because they're too long and draw the background
            $lineBackground = $foregroundColorEscapeCode + $gutterText + $backgroundColorEscapeCode + (" " * $codeWidth) + $resetEscapeCode
            if ($line.Length -gt $codeWidth) {
                # How many times can this line be wrapped in the code editor width available
                $wrappedLineSegments = ($line | Select-String -Pattern ".{1,$codeWidth}" -AllMatches).Matches.Value
                # Render the background line plus additional background lines without the gutter line number for each wrapped line
                $wrappedLinesBackground = (" " * $gutterSize) + $backgroundColorEscapeCode + (" " * $codeWidth) + $resetEscapeCode
                [Console]::WriteLine($lineBackground + ($wrappedLinesBackground * ($wrappedLineSegments.Count - 1)))
                # Correct terminal line position if the window scrolled
                $terminalLine = $Host.UI.RawUI.CursorPosition.Y - $wrappedLineSegments.Count
            } else {
                # Render the background
                [Console]::WriteLine($lineBackground)
                $terminalLine = $Host.UI.RawUI.CursorPosition.Y - 1
            }

            # Render the tokens that are on this line
            ($lineTokens | Where-Object { $_.Name -eq $functionLineNumber }).Group | ForEach-Object {
                if ($null -ne $_) {
                    Write-Token -Token $_ -TerminalLine $terminalLine -BackgroundRgb $BackgroundRgb -GutterSize $gutterSize -Highlight:$lineHighlight -Theme $Theme -SyntaxHighlight:$lineSyntax
                }
            }

            # Highlight all extents on this line that have been requested to be emphasized
            ($lineExtents | Where-Object { $_.Name -eq $functionLineNumber }).Group | Foreach-Object {
                if ($null -ne $_) {
                    Write-Token -Extent $_ -TerminalLine $terminalLine -BackgroundRgb $BackgroundRgb -GutterSize $gutterSize -Highlight -Theme $Theme
                }
            }

            $functionLineNumber++
        }
    } catch {
        throw $_
    } finally {
        [Console]::CursorVisible = $true
    }
}

function Expand-Tokens {
    <#
        .SYNOPSIS
            Split multiline tokens into "single line tokens" represented as hashtables.
        .DESCRIPTION
            Tokens can be multiline which makes rendering especially difficult when line wrapping of long tokens gets involved, it's
            easier to pre-split these multiline tokens into single line tokens before rendering them.
    #>
    param (
        [array] $Tokens
    )
    $splitTokens = @()
    if ($null -eq $Tokens -or $Tokens.Count -eq 0) {
        return $splitTokens
    }
    foreach ($token in $Tokens) {
        $tokenLines = $token.Text.Split("`n")
        $lineOffset = 0
        foreach ($tokenLine in $tokenLines) {
            # If it's the first line this tokens column is not set to 1 it has its own x position
            $startColumnNumber = 1
            if ($lineOffset -eq 0) {
                $startColumnNumber = $token.Extent.StartColumnNumber
            }
            $splitTokens += @{
                Text         = $tokenLine
                Extent       = @{
                    Text              = $tokenLine
                    StartColumnNumber = $startColumnNumber
                    StartLineNumber   = $token.Extent.StartLineNumber + $lineOffset
                }
                Kind         = $token.Kind
                TokenFlags   = $token.TokenFlags
                NestedTokens = @()
            }
            $lineOffset++
        }
        # Append nested tokens so they're expanded later than the parent and drawn overtop e.g. interpolated string variables
        $splitTokens += Expand-Tokens -Tokens $token.NestedTokens
    }
    return $splitTokens
}

function Get-TokenColor {
    <#
        .SYNOPSIS
            Given a syntax token provide a color based on its type.
    #>
    param (
        # The kind of token identified by the PowerShell language parser
        [System.Management.Automation.Language.TokenKind] $Kind,
        # TokenFlags identified by the PowerShell language parser
        [System.Management.Automation.Language.TokenFlags] $TokenFlags,
        # The theme to use to choose token colors
        [string] $Theme
    )
    $ForegroundRgb = switch -wildcard ($Kind) {
        "Function" { $script:Themes[$Theme].Function }
        "Generic" { $script:Themes[$Theme].Generic }
        "*String*" { $script:Themes[$Theme].String }
        "Variable" { $script:Themes[$Theme].Variable }
        "Identifier" { $script:Themes[$Theme].Identifier }
        "Number" { $script:Themes[$Theme].Number }
        default { $script:Themes[$Theme].Default }
    }
    if ($TokenFlags -like "*operator*" -or $TokenFlags -like "*keyword*") {
        $ForegroundRgb = $script:Themes[$Theme].Keyword
    }
    return $ForegroundRgb
}

function Write-Token {
    <#
        .SYNOPSIS
            Writes colored text to the console at a specific token location.
    #>
    param (
        # The token to write, this can be a hashtable/object representing a (System.Management.Automation.Language.Token) or a real one, I'm faking it to deal with multiline tokens
        [object] $Token,
        # The text to write from an extent (System.Management.Automation.Language.InternalScriptExtent)
        [object] $Extent,
        # The terminal line to start rendering from
        [int] $TerminalLine,
        # Render the token with syntax highlighting
        [switch] $SyntaxHighlight,
        # Highlight this token in a bright overlay color for emphasis
        [switch] $Highlight,
        # The width of the gutter for this codeblock
        [int] $GutterSize,
        # The color theme to use
        [string] $Theme
    )

    $ForegroundRgb = $script:Themes[$Theme].ForegroundRgb
    $BackgroundRgb = $script:Themes[$Theme].BackgroundRgb

    if ($Highlight) {
        $ForegroundRgb = $script:Themes[$Theme].HighlightRgb
    }

    if (!$Extent) {
        $Extent = $Token.Extent
    }

    $text = $Extent.Text
    $column = $Extent.StartColumnNumber

    $colorEscapeCode = ""
    if ($SyntaxHighlight -and $null -ne $Token) {
        $ForegroundRgb = Get-TokenColor -Kind $Token.Kind -TokenFlags $Token.TokenFlags -Theme $Theme
    }
    $colorEscapeCode += "$([Char]27)[38;2;{0};{1};{2}m" -f $ForegroundRgb.R, $ForegroundRgb.G, $ForegroundRgb.B
    if ($BackgroundRgb) {
        $colorEscapeCode += "$([Char]27)[48;2;{0};{1};{2}m" -f $BackgroundRgb.R, $BackgroundRgb.G, $BackgroundRgb.B
    }

    $consoleWidth = $Host.UI.RawUI.WindowSize.Width - $GutterSize
    
    try {
        $initialCursorSetting = [Console]::CursorVisible
    } catch {
        $initialCursorSetting = $true
    }
    $initialCursorPosition = $Host.UI.RawUI.CursorPosition
    [Console]::CursorVisible = $false
    try {
        $textToRender = @()
        # Overruns are parts of this extent that extend beyond the width of the terminal and need their own line wrapping
        $overrunText = @()
        # This extent might be on a wrapped part of this line, make sure to find the correct start point
        $columnIndex = $Column - 1
        $wrappedLineIndex = [Math]::Floor($columnIndex / $consoleWidth)
        $x = ($columnIndex % $consoleWidth) + $GutterSize
        $y = $wrappedLineIndex
        # Handle extent running beyond the width of the terminal
        if (($x + $text.Length) -gt ($consoleWidth + $GutterSize)) {
            $fullExtentLine = $text
            $endOfTextOnCurrentLine = $consoleWidth - $x + $GutterSize
            $text = $text.Substring(0, $endOfTextOnCurrentLine)
            $remainingText = $fullExtentLine.Substring($endOfTextOnCurrentLine, $fullExtentLine.Length - $endOfTextOnCurrentLine)
            if ($remainingText.Length -gt $consoleWidth) {
                $overrunText += ($remainingText | Select-String "(.{1,$consoleWidth})+").Matches.Groups[1].Captures.Value
            } else {
                $overrunText += $remainingText
            }
        }

        $textToRender += @{
            Text = $text
            X    = $x
            Y    = $y
        }

        # Prepare any parts of this line that extended beyond the width of the terminal
        $overruns = 0
        foreach ($overrun in $overrunText) {
            $overruns++
            $textToRender += @{
                Text = $overrun
                X    = $GutterSize
                Y    = $y + $overruns
            }
        }

        $textToRender | Foreach-Object {
            [Console]::SetCursorPosition($_.X, $TerminalLine + $_.Y)
            [Console]::Write($colorEscapeCode + $_.Text + "$([Char]27)[0m")
        }
    } catch {
        throw $_
    } finally {
        [Console]::CursorVisible = $initialCursorSetting
        [Console]::SetCursorPosition($initialCursorPosition.X, $initialCursorPosition.Y)
    }
}


#endregion


#region PwshSpectreConsole/private/Add-SpectreTreeNode.ps1


<#
.SYNOPSIS
Recursively adds child nodes to a parent node in a Spectre.Console tree.

.DESCRIPTION
The Add-SpectreTreeNode function adds child nodes to a parent node in a Spectre.Console tree. It does this recursively, so it can handle nested child nodes.

.PARAMETER Node
The parent node to which the child nodes will be added.

.PARAMETER Children
An array of child nodes to be added to the parent node. Each child node should be an object with a 'Label' property and a 'Children' property (which can be an empty array if the child has no children of its own).

.NOTES
See Format-SpectreTree for usage.
#>
function Add-SpectreTreeNode {
    param (
        [Parameter(Mandatory)]
        [Spectre.Console.IHasTreeNodes] $Node,
        [Parameter(Mandatory)]
        [array] $Children
    )

    foreach ($child in $Children) {
        
        # Backwards compatibility: Value used to be called Label
        if ($child.ContainsKey("Label")) {
            $child["Value"] = $child["Label"]
            $child.Remove("Label")
        }

        $newNode = [Spectre.Console.HasTreeNodeExtensions]::AddNode($Node, $child.Value)
        if ($child.Children.Count -gt 0) {
            Add-SpectreTreeNode -Node $newNode -Children $child.Children
        }
    }
}


#endregion


#region PwshSpectreConsole/private/Add-TableColumns.ps1


function Add-TableColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Spectre.Console.Table] $table,
        [Collections.Specialized.OrderedDictionary] $FormatData,
        [String] $Title,
        [Spectre.Console.Color] $Color = [Spectre.Console.Color]::Default,
        [Switch] $Scalar,
        [Switch] $Wrap
    )
    Write-Debug "Module: $($ExecutionContext.SessionState.Module.Name) Command: $($MyInvocation.MyCommand.Name) Param: $($PSBoundParameters.GetEnumerator())"
    if ($Scalar) {
        if ($Title) {
            Write-Debug "Adding column with title: $Title"
            $table.AddColumn("[$($Color.ToMarkup())]$Title[/]") | Out-Null
        } else {
            Write-Debug "Adding column with title: Value"
            $table.AddColumn("[$($Color.ToMarkup())]Value[/]") | Out-Null
        }
        if (-Not $Wrap) {
            $table.Columns[-1].NoWrap = $true
        }
    } else {
        foreach ($key in $FormatData.keys) {
            $lookup = $FormatData[$key]
            Write-Debug "Adding column from formatdata: $($lookup.GetEnumerator())"
            $table.AddColumn("[$($Color.ToMarkup())]$($lookup.Label)[/]") | Out-Null
            $table.Columns[-1].Padding = [Spectre.Console.Padding]::new(1, 0, 1, 0)
            if ($lookup.width -gt 0) {
                # width 0 is autosize, select the last entry in the column list
                $table.Columns[-1].Width = $lookup.Width
            }
            if ($lookup.Alignment -ne 'undefined') {
                $table.Columns[-1].Alignment = [Spectre.Console.Justify]::$lookup.Alignment
            }
            if (-Not $Wrap) {
                # https://github.com/spectreconsole/spectre.console/issues/1185
                # leaving it in as it will probably get fixed, has no effect on output yet.
                $table.Columns[-1].NoWrap = $true
            }
        }
    }
    return $table
}


#endregion


#region PwshSpectreConsole/private/Clear-InputQueue.ps1


# Required for unit test mocking in Read-SpectrePause
# This drains the input buffer so if the user has pressed enter or any other key, it won't be read by the following prompt
function Clear-InputQueue {
    while ([System.Console]::KeyAvailable) {
        $null = [System.Console]::ReadKey($true)
    }
}


#endregion


#region PwshSpectreConsole/private/Convert-HashtableToRenderSafePSObject.ps1


function Convert-HashtableToRenderSafePSObject {
    param(
        [object] $Hashtable,
        [hashtable] $Renderables
    )
    $customObject = [ordered]@{}
    foreach ($item in $Hashtable.GetEnumerator()) {
        if ($item.Value -is [hashtable] -or $item.Value -is [ordered]) {
            $item.Value = Convert-HashtableToRenderSafePSObject -Hashtable $item.Value
        } elseif ($item.Value -is [Spectre.Console.Rendering.Renderable]) {
            $renderableKey = "RENDERABLE__$([Guid]::NewGuid().Guid)"
            $Renderables[$renderableKey] = $item.Value
            $item.Value = $renderableKey
        }
        $customObject[$item.Key] = $item.Value
    }
    return [pscustomobject]$customObject
}


#endregion


#region PwshSpectreConsole/private/Convert-ToSpectreColor.ps1


<#
.SYNOPSIS
Converts a string representation of a color to a Color object.

.DESCRIPTION
This function takes a string representation of a color and converts it to a Color object. The input color can be in the form of a named color or a hexadecimal color code.

.PARAMETER Color
The color to convert. This parameter is mandatory and accepts input from the pipeline.

.EXAMPLE
'red' | Convert-ToSpectreColor

.EXAMPLE
'#FF0000' | Convert-ToSpectreColor

.EXAMPLE
[Spectre.Console.Color]::Salmon1 | Convert-ToSpectreColor
#>
function Convert-ToSpectreColor {
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [object] $Color
    )
    try {
        # Just return the console color object
        if ($Color -is [Spectre.Console.Color]) {
            return $Color
        }
        # Already validated in validation attribute
        if ($Color.StartsWith("#")) {
            $hexString = $Color -replace '^#', ''
            $hexBytes = [System.Convert]::FromHexString($hexString)
            return [Spectre.Console.Color]::new($hexBytes[0], $hexBytes[1], $hexBytes[2])
        }

        # Validated in attribute as a real color already
        return [Spectre.Console.Color]::$Color
    } catch {
        return $script:AccentColor
    }
}


#endregion


#region PwshSpectreConsole/private/ConvertFrom-ConsoleColor.ps1


function ConvertFrom-ConsoleColor {
    param(
        [int]$Color
    )
    Write-Debug "Module: $($ExecutionContext.SessionState.Module.Name) Command: $($MyInvocation.MyCommand.Name) Param: $($PSBoundParameters.GetEnumerator())"
    $consoleColors = @{
        30  = 'Black'
        31  = 'DarkRed'
        32  = 'DarkGreen'
        33  = 'DarkYellow'
        34  = 'DarkBlue'
        35  = 'DarkMagenta'
        36  = 'DarkCyan'
        37  = 'Gray'
        40  = 'Black'
        41  = 'DarkRed'
        42  = 'DarkGreen'
        43  = 'DarkYellow'
        44  = 'DarkBlue'
        45  = 'DarkMagenta'
        46  = 'DarkCyan'
        47  = 'Gray'
        90  = 'DarkGray'
        91  = 'Red'
        92  = 'Green'
        93  = 'Yellow'
        94  = 'Blue'
        95  = 'Magenta'
        96  = 'Cyan'
        97  = 'White'
        100 = 'DarkGray'
        101 = 'Red'
        102 = 'Green'
        103 = 'Yellow'
        104 = 'Blue'
        105 = 'Magenta'
        106 = 'Cyan'
        107 = 'White'
    }
    return $consoleColors[$Color]
}


#endregion


#region PwshSpectreConsole/private/ConvertTo-Renderable.ps1


function ConvertTo-Renderable {
    param (
        [Parameter(ValueFromPipeline)]
        [object] $InputData
    )

    # These objects are already renderable
    if ($InputData -is [Spectre.Console.Rendering.Renderable]) {
        return $InputData
    }

    $renderableItems = @()
    
    if ($InputData -is [array]) {
        foreach ($column in $InputData) {
            $renderableItems += ConvertTo-Renderable $column
        }
    } else {
        # For others just dump them as either strings formatted with markup which are easy to identify by the closing tag [/] or as plain text
        if ($InputData -like "*[/]*") {
            $renderableItems += [Spectre.Console.Markup]::new($InputData)
        } else {
            $renderableItems += [Spectre.Console.Text]::new(($InputData | Out-String -NoNewline))
        }
    }

    return $renderableItems
}


#endregion


#region PwshSpectreConsole/private/Get-ControlSequenceResponse.ps1


<#
.SYNOPSIS
Reads a control sequence response from the console.

.DESCRIPTION
Reads a control sequence response from the console.

.PARAMETER ControlSequence
The control sequence to send to the console.

.EXAMPLE
# **Example 1**
# This example demonstrates how to read a control sequence response from the console.
$response = Get-ControlSequenceResponse -ControlSequence "[c"
#>
function Get-ControlSequenceResponse {
    param (
        [Parameter(Mandatory)]
        [string] $ControlSequence
    )
    $char = $null
    [console]::Write([char]27 + $ControlSequence)
    $response = do {
            $char = [console]::ReadKey($true).KeyChar
            $char
        } while ($char -ne 'c' -and [Console]::KeyAvailable)
    return -join $response
}


#endregion


#region PwshSpectreConsole/private/Get-HostHeight.ps1


# Required for unit test mocking
function Get-HostHeight {
    return $Host.UI.RawUI.WindowSize.Height
}


#endregion


#region PwshSpectreConsole/private/Get-HostWidth.ps1


# Required for unit test mocking
function Get-HostWidth {
    return [Spectre.Console.AnsiConsole]::Profile.Width
}


#endregion


#region PwshSpectreConsole/private/Get-TableHeader.ps1


function Get-TableHeader {
    <#
        ls | ft | Get-TableHeader
        https://gist.github.com/Jaykul/9999be71ee68f3036dc2529c451729f4
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        $FormatStartData
    )
    begin {
        Write-Debug "Module: $($ExecutionContext.SessionState.Module.Name) Command: $($MyInvocation.MyCommand.Name) Param: $($PSBoundParameters.GetEnumerator())"
        $alignment = @{
            0 = 'undefined'
            1 = 'Left'
            2 = 'Center'
            3 = 'Right'
        }
    }
    process {
        if ($FormatStartData.Gettype().Name -eq 'FormatStartData') {
            $properties = [ordered]@{}
            $FormatStartData.shapeinfo.tablecolumninfolist | Where-Object { $_ } | ForEach-Object {
                $Name = $_.Label ? $_.Label : $_.propertyName
                $properties[$Name] = @{
                    Label                 = $Name
                    Width                 = $_.width
                    Alignment             = $alignment.Contains($_.alignment) ? $alignment[$_.alignment] : 'undefined'
                    HeaderMatchesProperty = $_.HeaderMatchesProperty
                    # PropertyName          = $_.propertyName
                }
            }
            if ($properties.Keys.Count -eq 0) {
                Write-Debug "No properties found"
                return $null
            }
            return $properties
        }
    }
}


#endregion


#region PwshSpectreConsole/private/Initialize-SpectreConsoleDimensions.ps1


<#
.SYNOPSIS
Initializes or ensures valid Spectre Console dimensions.

.DESCRIPTION
This function ensures that the Spectre Console has valid width and height dimensions.
If dimensions are invalid (0 or negative), it sets default values (80x24).
This is particularly important in CI environments where console dimensions may not be properly defined.

.PARAMETER DefaultWidth
The default width to use if the console width is invalid. Defaults to 80.

.PARAMETER DefaultHeight
The default height to use if the console height is invalid. Defaults to 24.
#>
function Initialize-SpectreConsoleDimensions {
    [CmdletBinding()]
    param (
        [int] $DefaultWidth = 80,
        [int] $DefaultHeight = 24
    )

    # Get current dimensions
    $width = [Spectre.Console.AnsiConsole]::Console.Profile.Width
    $height = [Spectre.Console.AnsiConsole]::Console.Profile.Height
    
    # Set default values if width or height is 0 or negative
    if ($width -le 0) {
        [Spectre.Console.AnsiConsole]::Console.Profile.Width = $DefaultWidth
    }
    
    if ($height -le 0) {
        [Spectre.Console.AnsiConsole]::Console.Profile.Height = $DefaultHeight
    }
}


#endregion


#region PwshSpectreConsole/private/Invoke-SpectrePromptAsync.ps1


function Invoke-SpectrePromptAsync {
    <#
    .SYNOPSIS
    Shows a Spectre.Console prompt.

    .DESCRIPTION
    This function shows a Spectre.Console prompt "asynchronously" in PowerShell by faking the async call. By allowing the prompt to run asynchronously in the background and polling for its completion, it allows ctrl-c interrupts to continue to work within the single-threaded PowerShell world.

    .PARAMETER Prompt
    The Spectre.Console prompt to show.

    .EXAMPLE
    $result = Invoke-SpectrePromptAsync $prompt
    #>
    param (
        [Parameter(Mandatory)]
        $Prompt,
        [int] $TimeoutSeconds
    )

    $timeout = $null
    if ($TimeoutSeconds) {
        $timeout = (Get-Date).AddSeconds($TimeoutSeconds)
        Write-SpectreHost "[$script:DefaultValueColor]This prompt times out in $TimeoutSeconds seconds...[/]`n"
    }

    $cts = [System.Threading.CancellationTokenSource]::new()
    try {
        $task = $Prompt.ShowAsync([Spectre.Console.AnsiConsole]::Console, $cts.Token)
        while (-not $task.AsyncWaitHandle.WaitOne(200)) {
            # Waiting for the async task this way allows ctrl-c interrupts to continue to work within the single-threaded PowerShell world
            if ($null -ne $timeout -and (Get-Date) -ge $timeout) {
                $cts.Cancel()
                Write-SpectreHost "`n`n[$script:DefaultValueColor]Prompt timed out[/]"
            }
        }
        if (!$task.IsCanceled) {
            return $task.GetAwaiter().GetResult()
        }
    } finally {
        $cts.Cancel()
        $task.Dispose()
    }
}


#endregion


#region PwshSpectreConsole/private/Merge-HashtableDefaults.ps1


function Merge-HashtableDefaults {
    param(
        [hashtable] $UserStyle,
        [hashtable] $DefaultStyle
    )
    foreach ($key in $UserStyle.Keys) {
        if (-not $DefaultStyle.ContainsKey($key)) {
            Write-Warning "Key '$key' is not a valid default style property and will be ignored, styles must be one of $($DefaultStyle.Keys -join ', ')."
        }
    }
    foreach ($key in $DefaultStyle.Keys) {
        if (-not $UserStyle.ContainsKey($key)) {
            $UserStyle[$key] = $DefaultStyle[$key]
        }
    }
}


#endregion


#region PwshSpectreConsole/private/New-TableCell.ps1


function New-TableCell {
    [cmdletbinding()]
    param(
        [Object] $CellData,
        [Spectre.Console.Color] $Color = [Spectre.Console.Color]::Default,
        [Switch] $AllowMarkup
    )
    Write-Debug "Module: $($ExecutionContext.SessionState.Module.Name) Command: $($MyInvocation.MyCommand.Name) Param: $($PSBoundParameters.GetEnumerator())"

    # Spectre console already knows how to format its own renderables, this allows embedding spectre widgets inside table cells
    if ($CellData -is [Spectre.Console.Rendering.Renderable]) {
        return $CellData
    }

    if ([String]::IsNullOrEmpty($CellData)) {
        if ($AllowMarkup) {
            return [Spectre.Console.Markup]::new(' ', [Spectre.Console.Style]::new($Color))
        }
        return [Spectre.Console.Text]::new(' ', [Spectre.Console.Style]::new($Color))
    }
    if (-Not [String]::IsNullOrEmpty($CellData.ToString())) {
        if ($AllowMarkup) {
            Write-Debug "New-TableCell ToString(), Markup, $($CellData.ToString())"
            return [Spectre.Console.Markup]::new($CellData.ToString(), [Spectre.Console.Style]::new($Color))
        }
        Write-Debug "New-TableCell ToString(), Text, $($CellData.ToString())"
        return [Spectre.Console.Text]::new($CellData.ToString(), [Spectre.Console.Style]::new($Color))
    }
    # just coerce to string.
    if ($AllowMarkup) {
        Write-Debug "New-TableCell [String], markup, $([String]$CellData)"
        return [Spectre.Console.Markup]::new([String]$CellData, [Spectre.Console.Style]::new($Color))
    }
    Write-Debug "New-TableCell [String], Text, $([String]$CellData)"
    return [Spectre.Console.Text]::new([String]$CellData, [Spectre.Console.Style]::new($Color))
}


#endregion


#region PwshSpectreConsole/private/New-TableRow.ps1


function New-TableRow {
    param(
        [Parameter(Mandatory)]
        [Object] $Entry,
        [Spectre.Console.Color] $Color = [Spectre.Console.Color]::Default,
        [Switch] $AllowMarkup,
        [Switch] $Scalar,
        [hashtable] $Renderables
    )
    Write-Debug "Module: $($ExecutionContext.SessionState.Module.Name) Command: $($MyInvocation.MyCommand.Name) Param: $($PSBoundParameters.GetEnumerator())"
    $opts = @{
        AllowMarkup = $AllowMarkup
    }
    if ($scalar) {
        # Swap spectre renderable objects with the raw object
        $name = $Entry.ToString()
        if ($name.StartsWith("RENDERABLE__")) {
            $Entry = $renderables[$name]
        }
        New-TableCell -CellData $Entry -Color $Color @opts
    } else {
        # simplified, should be faster.
        $detectVT = '\x1b'
        $rows = foreach ($cell in $Entry) {
            if ([String]::IsNullOrEmpty($cell)) {
                New-TableCell -Color $Color @opts
                continue
            }
            if ($cell -match $detectVT) {
                # Use optimized fast paragraph to reduce allocations
                $fp = [PwshSpectreConsole.VTParser]::ToSpanParagraph($cell)
                if ($null -ne $fp) { $fp.SingleLineOverride = $true; $fp }
                continue
            }
            # Swap spectre renderable objects with the raw spectre renderable object
            $name = $cell.ToString()
            if ($name.StartsWith("RENDERABLE__")) {
                $cell = $renderables[$name]
            }
            New-TableCell -CellData $cell -Color $Color @opts
        }
        return $rows
    }
}


#endregion


#region PwshSpectreConsole/private/Read-ConsoleKey.ps1


function Read-ConsoleKey {
    return [console]::ReadKey($true)
}


#endregion


#region PwshSpectreConsole/private/Read-FigletFont.ps1


# Read in a figlet font or just return the default built-in one
function Read-FigletFont {
    param (
        [string] $FigletFontPath
    )
    $figletFont = [Spectre.Console.FigletFont]::Default
    if ($FigletFontPath) {
        if (!(Test-Path $FigletFontPath)) {
            throw "The specified Figlet font file '$FigletFontPath' does not exist"
        }
        $fullPath = (Resolve-Path $FigletFontPath).Path
        $figletFont = [Spectre.Console.FigletFont]::Load($fullPath)
    }
    return $figletFont
}


#endregion


#region PwshSpectreConsole/private/Set-CursorPosition.ps1


# Required for unit test mocking in Read-SpectrePause
# Set the cursor to an arbitrary window position
function Set-CursorPosition {
    param (
        [int] $X,
        [int] $Y
    )
    [Console]::SetCursorPosition($X, $Y)
}


#endregion


#region PwshSpectreConsole/private/Start-AnsiConsoleLive.ps1


<#
.SYNOPSIS
Starts an ANSI console live renderable.

.DESCRIPTION
This function is required for mocking ansiconsole in unit tests that write objects to the console.
It ensures that the console has valid dimensions before starting the live display, which is particularly important in CI environments.

.PARAMETER Data
The renderable object to display.

.PARAMETER ScriptBlock
The script block to execute while the live renderable is being rendered.
#>
function Start-AnsiConsoleLive {
    param (
        [Parameter(Mandatory)]
        [Spectre.Console.Rendering.Renderable] $Data,
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock
    )
    $resultVariableName = "AnsiConsoleLiveResult-$([guid]::NewGuid())"
    New-Variable -Name $resultVariableName -Scope "Script"
    
    # Ensure console has valid dimensions before starting live display
    Initialize-SpectreConsoleDimensions
    
    try {
        [Spectre.Console.AnsiConsole]::Live($Data).Start({
            param (
                [Spectre.Console.LiveDisplayContext] $Context
            )
            Set-Variable -Name $resultVariableName -Value (& $ScriptBlock $Context) -Scope "Script"
        })
    }
    finally {
        # No need to restore dimensions, handled by Initialize-SpectreConsoleDimensions
    }
    return Get-Variable -Name $resultVariableName -ValueOnly
}


#endregion


#region PwshSpectreConsole/private/Start-AnsiConsoleProgress.ps1


<#
.SYNOPSIS
Starts an ANSI console progress bar.

.DESCRIPTION
This function is required for mocking ansiconsole in unit tests that write objects to the console.

.PARAMETER ScriptBlock
The script block to execute while the progress bar is running.

.EXAMPLE
Start-AnsiConsoleProgress {
    # Some long-running operation
}
#>
function Start-AnsiConsoleProgress {
    param (
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock
    )
    $resultVariableName = "AnsiConsoleProgressResult-$([guid]::NewGuid())"
    New-Variable -Name $resultVariableName -Scope "Script"
    [Spectre.Console.AnsiConsole]::Progress().Start({
            param (
                $ctx
            )
            Set-Variable -Name $resultVariableName -Value (& $ScriptBlock $ctx) -Scope "Script"
        })
    return Get-Variable -Name $resultVariableName -ValueOnly
}


#endregion


#region PwshSpectreConsole/private/Start-AnsiConsoleStatus.ps1


function Start-AnsiConsoleStatus {
    param (
        [Parameter(Mandatory)]
        [string] $Title,
        [Parameter(Mandatory)]
        [Spectre.Console.Spinner] $Spinner,
        [Parameter(Mandatory)]
        [Spectre.Console.Style] $SpinnerStyle,
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock
    )
    $resultVariableName = "AnsiConsoleStatusResult-$([guid]::NewGuid())"
    New-Variable -Name $resultVariableName -Scope "Script"
    [Spectre.Console.AnsiConsole]::Status().Start($Title, {
            param (
                $ctx
            )
            $ctx.Spinner = $Spinner
            $ctx.SpinnerStyle = $SpinnerStyle
            Set-Variable -Name $resultVariableName -Value (& $ScriptBlock $ctx) -Scope "Script"
        })
    return Get-Variable -Name $resultVariableName -ValueOnly
}


#endregion


#region PwshSpectreConsole/private/Test-IsScalar.ps1


function Test-IsScalar {
    [CmdletBinding()]
    param(
        $Value
    )
    Write-Debug "Module: $($ExecutionContext.SessionState.Module.Name) Command: $($MyInvocation.MyCommand.Name) Param: $($PSBoundParameters.GetEnumerator())"
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $Value = $Value | Select-Object -First 1
    }
    return $Value -is [System.ValueType] -or $Value -is [System.String]
}


#endregion


#region PwshSpectreConsole/private/Test-SpectreSixelSupport.ps1


function Test-SpectreSixelSupport {
    <#
    .SYNOPSIS
        Tests if the terminal supports Sixel graphics.
    .DESCRIPTION
        Tests if the terminal supports Sixel graphics. Sixel allows the terminal to display images.
        Windows Terminal Preview and other terminals support sixel, see https://www.arewesixelyet.com/ for more.
        Returns $true if the terminal supports Sixel graphics, otherwise $false.
    #>
    [Reflection.AssemblyMetadata("title", "Test-SpectreSixelSupport")]
    param ()
    try {
        [PwshSpectreConsole.Terminal.Compatibility]::TerminalSupportsSixel()
    } catch {
        return $false
    }
}


#endregion


#region PwshSpectreConsole/private/Write-AnsiConsole.ps1


<#
.SYNOPSIS
Writes an object to the console using [Spectre.Console.AnsiConsole]::Write()

.DESCRIPTION
This function is required for mocking ansiconsole in unit tests that write objects to the console.

.PARAMETER RenderableObject
The renderable object to write to the console e.g. [Spectre.Console.BarChart]

.EXAMPLE
Write-SpectreConsoleOutput -Object "Hello, World!" -ForegroundColor Green -BackgroundColor Black
#>
function Write-AnsiConsole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [RenderableTransformationAttribute()]
        [object] $RenderableObject,
        [switch] $CustomItemFormatter
    )

    if ($script:SpectreRecordingType) {
        [Spectre.Console.AnsiConsole]::Write($RenderableObject)
        return
    }

    if ($CustomItemFormatter) {
        # ps1xml CustomItem formatters mangle the output because it uses the last character of the buffer width for itself
        $script:SpectreConsole.Profile.Width = $Host.UI.RawUI.BufferSize.Width - 1
    } else {
        $script:SpectreConsole.Profile.Width = $Host.UI.RawUI.BufferSize.Width
    }

    $script:SpectreConsole.Write($RenderableObject)
    $output = $script:SpectreConsoleWriter.ToString().TrimEnd()
    $null = $script:SpectreConsoleWriter.GetStringBuilder().Clear()

    # If it contains sixel data and is from the custom item formatter then we need to write it to the console directly :(
    # I'm not sure why this is the case but it's the only way to get the sixel data to render correctly at the moment
    # This also affects items using link data because long links get line broken and the link is lost and rendering gets mangled
    if (($output -like "*P0;1q*" -or $output -like "*]8;id=*") -and $CustomItemFormatter) {
        "`n" + $output + "`e[2A" | Out-Host
        return
    } else {
        return $output
    }
}


#endregion


#region PwshSpectreConsole/private/Write-AnsiConsoleWithWidth.ps1


<#
.SYNOPSIS
Writes an object to the console using Spectre.Console with a specific width

.DESCRIPTION
This function writes a renderable object to the console with a specific width.

.PARAMETER RenderableObject
The renderable object to write to the console e.g. [Spectre.Console.Rule]

.PARAMETER MaxWidth
The maximum width to use for rendering

.EXAMPLE
Write-AnsiConsoleWithWidth -RenderableObject $rule -MaxWidth 40
#>
function Write-AnsiConsoleWithWidth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [RenderableTransformationAttribute()]
        [object] $RenderableObject,
        
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int] $MaxWidth
    )

    if ($script:SpectreRecordingType) {
        $originalRecordingWidth = [Spectre.Console.AnsiConsole]::Console.Profile.Width
        try {
            [Spectre.Console.AnsiConsole]::Console.Profile.Width = $MaxWidth
            [Spectre.Console.AnsiConsole]::Write($RenderableObject)
        } finally {
            [Spectre.Console.AnsiConsole]::Console.Profile.Width = $originalRecordingWidth
        }
        return
    }

    # Save the original width
    $originalWidth = $script:SpectreConsole.Profile.Width
    
    try {
        # Set the temporary width for rendering
        $script:SpectreConsole.Profile.Width = $MaxWidth
        
        # Render the object
        $script:SpectreConsole.Write($RenderableObject)
        $output = $script:SpectreConsoleWriter.ToString().TrimEnd()
        $null = $script:SpectreConsoleWriter.GetStringBuilder().Clear()
        
        return $output
    }
    finally {
        # Restore the original width
        $script:SpectreConsole.Profile.Width = $originalWidth
    }
}


#endregion


#region PwshSpectreConsole/private/Write-SpectreHostInternal.ps1


# Functions required for unit testing write-spectrehost
function Write-SpectreHostInternalMarkup {
    param (
        [string] $Message,
        [ValidateSet([SpectreConsoleJustify], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string] $Justify = "Left",
        [switch] $NoNewline,
        [switch] $PassThru
    )

    # If the message is empty, set it to a space. Spectre Console doesn't like empty strings for this.
    if ($Message -eq "") {
        $Message = " "
    }

    if ($PassThru) {
        # NewLine isn't required for PassThru
        $output = [Spectre.Console.Markup]::new($Message)
        $output.Justification = [Spectre.Console.Justify]::$Justify
        return $output
    }

    if (-not $NoNewline) {
        $Message += "`n"
    }

    $output = [Spectre.Console.Markup]::new($Message)
    $output.Justification = [Spectre.Console.Justify]::$Justify

    [Spectre.Console.AnsiConsole]::Write($output)
}


#endregion


#region PwshSpectreConsole/public/config/Get-SpectreColors.ps1


function Get-SpectreColors {
    <#
    .SYNOPSIS
    Gets the current default colors for Spectre Console.

    .DESCRIPTION
    This function returns the current default color configuration for Spectre Console. These colors are used throughout the module as defaults for various commands. The colors can be changed using Set-SpectreColors.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to retrieve the current default colors for Spectre Console.
    Get-SpectreColors | Format-SpectreTable

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to retrieve the default colors after changing them with Set-SpectreColors.
    Set-SpectreColors -AccentColor "Turquoise2" -DefaultValueColor "Grey85"
    Get-SpectreColors | Format-SpectreTable
    Set-SpectreColors -AccentColor "Blue" -DefaultValueColor "Grey"

    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/config/get-spectrecolors/')]
    [Reflection.AssemblyMetadata("title", "Get-SpectreColors")]
    param ()
    return [PSCustomObject]@{
        AccentColor           = $script:AccentColor
        DefaultValueColor     = $script:DefaultValueColor
        DefaultTableHeaderColor = $script:DefaultTableHeaderColor
        DefaultTableTextColor = $script:DefaultTableTextColor
    }
}


#endregion


#region PwshSpectreConsole/public/config/Get-SpectreProfile.ps1


function Get-SpectreProfile {
    [CmdletBinding()]
    param ()
    $object = [Spectre.Console.AnsiConsole]::Profile
    return [PSCustomObject]@{
        Enrichers             = $object.Enrichers -join ', '
        ColorSystem           = $object.Capabilities.ColorSystem
        Unicode               = $object.Capabilities.Unicode
        Ansi                  = $object.Capabilities.Ansi
        Links                 = $object.Capabilities.Links
        Legacy                = $object.Capabilities.Legacy
        Interactive           = $object.Capabilities.Interactive
        Terminal              = $object.out.IsTerminal
        Writer                = $object.Out.Writer
        Width                 = $object.Width
        Height                = $object.Height
        Encoding              = $object.Encoding.EncodingName
        PSStyle               = $PSStyle.OutputRendering
        ConsoleOutputEncoding = [console]::OutputEncoding
        ConsoleInputEncoding  = [console]::InputEncoding
    }
}


#endregion


#region PwshSpectreConsole/public/config/Set-SpectreColors.ps1


function Set-SpectreColors {
    <#
    .SYNOPSIS
    Sets the accent color and default value color for Spectre Console.

    .DESCRIPTION
    This function sets the accent color and default value color for Spectre Console. The accent color is used for highlighting important information, while the default value color is used for displaying default values.

    .PARAMETER AccentColor
    The accent color to set. Must be a valid Spectre Console color name. Defaults to "Blue".

    .PARAMETER DefaultValueColor
    The default value color to set. Must be a valid Spectre Console color name. Defaults to "Grey".

    .PARAMETER DefaultTableHeaderColor
    The default table header color to set. Must be a valid Spectre Console color name. Defaults to "Default" which will be the standard console foreground color.

    .PARAMETER DefaultTableTextColor
    The default table text color to set. Must be a valid Spectre Console color name. Defaults to "Default" which will be the standard console foreground color.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to set the accent color and default value color for Spectre Console.
    Write-SpectreRule "This is a default rule"
    Set-SpectreColors -AccentColor "Turquoise2"
    Write-SpectreRule "This is a Turquoise2 rule"
    Write-SpectreRule "This is a rule with a specified color" -Color "Yellow"

    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/config/set-spectrecolors/')]
    [Reflection.AssemblyMetadata("title", "Set-SpectreColors")]
    param (
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $AccentColor = "Blue",
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $DefaultValueColor = "Grey",
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $DefaultTableHeaderColor = [Spectre.Console.Color]::Default,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $DefaultTableTextColor = [Spectre.Console.Color]::Default
    )
    $script:AccentColor = $AccentColor
    $script:DefaultValueColor = $DefaultValueColor
    $script:DefaultTableHeaderColor = $DefaultTableHeaderColor
    $script:DefaultTableTextColor = $DefaultTableTextColor
}


#endregion


#region PwshSpectreConsole/public/config/Start-SpectreRecording.ps1


$script:SpectreRecordingRecorder = $null
$script:SpectreRecordingOriginalConsole = $null
$script:SpectreRecordingType = $null

function Start-SpectreRecording {
    <#
        .SYNOPSIS
            Starts a recording of the current console output. This can be used to record a demo of a script or module.
        .DESCRIPTION
            Starts a recording of the current console output. This can be used to record all of the spectre console interactions in a PowerShell session.  
            I've used this to record the examples on the docs help site.
            :::caution
            This is experimental.  
            Experimental features are unstable and subject to change.
            :::
        .PARAMETER Width
            The width of the recording.
        .PARAMETER Height
            The height of the recording.
        .PARAMETER RecordingType
            The type of recording to create.
        .PARAMETER CountdownAndClear
            If this switch is present, the console will be cleared and a countdown will be displayed before the recording starts.
        .EXAMPLE
            # **Example 1**  
            # This example demonstrates how to record the spectre console output.
            $recording = Start-SpectreRecording -RecordingType "Html" -CountdownAndClear
            # Use spectre console functions, these will be recorded
            Write-SpectreHost "Hello [red]world[/]"
            # Finish the recording
            $result = Stop-SpectreRecording
            # Output the results
            Write-SpectreHost "Result:`n$result"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/config/start-spectrerecording/')]
    [Reflection.AssemblyMetadata("title", "Start-SpectreRecording")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Scope = 'Function', Target = '*')]
    param(
        [int] $Width = (Get-HostWidth),
        [int] $Height = (Get-HostHeight),
        [ValidateSet("asciinema", "text", "html")]
        [string] $RecordingType = "asciinema",
        [switch] $CountdownAndClear
    )

    if($script:SpectreRecordingType) {
        throw "A $script:SpectreRecordingType recording has already started"
    }

    if($CountdownAndClear) {
        function Test-Recording {
            for($i = 3; $i -gt 0; $i--) {
                [Console]::CursorVisible = $false
                Write-SpectreHost "`r:red_circle: Recording starting in $i"
                Start-Sleep -Seconds 1
                Write-SpectreHost ("`e[1A                                  " | Get-SpectreEscapedText) -NoNewline
            }
            Write-SpectreHost ("`rRecording started" | Get-SpectreEscapedText)
            [Console]::CursorVisible = $true
        }
    }

    $script:SpectreRecordingOriginalConsole = [Spectre.Console.AnsiConsole]::Console

    if($RecordingType -eq "asciinema") {
        # Create a recording console for asciinema, it's a bit fiddlier and requires an iansiconsole that can record durations between frames
        $script:SpectreRecordingRecorder = [PwshSpectreConsole.RecordingConsole]::new($width, $height)
    } else {
        # Use the built in recorder
        $script:SpectreRecordingRecorder = [Spectre.Console.Recorder]::new($script:SpectreRecordingOriginalConsole)
    }

    # Override current spectre console instance
    $script:SpectreRecordingType = $RecordingType
    [Spectre.Console.AnsiConsole]::Console = $script:SpectreRecordingRecorder

    return $script:SpectreRecordingRecorder
}


#endregion


#region PwshSpectreConsole/public/config/Stop-SpectreRecording.ps1


function Stop-SpectreRecording {
    <#
        .SYNOPSIS
            Stops a recording of the current console output and returns the recording.
        .DESCRIPTION
            Stops a recording of the current console output and returns the recording.  
            I've used this to record the examples on the docs help site.
            :::caution
            This is experimental.  
            Experimental features are unstable and subject to change.
            :::
        .PARAMETER Title
            The title of the recording, only used for asciinema recordings.
        .PARAMETER OutputPath
            The path to save the recording to.
        .EXAMPLE
            # **Example 1**  
            # This example demonstrates how to record the spectre console output.
            $recording = Start-SpectreRecording -RecordingType "Html" -CountdownAndClear
            # Use spectre console functions, these will be recorded
            Write-SpectreHost "Hello [red]world[/]"
            # Finish the recording
            $result = Stop-SpectreRecording
            # Output the results
            Write-SpectreHost "Result:`n$result"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/config/stop-spectrerecording/')]
    [Reflection.AssemblyMetadata("title", "Stop-SpectreRecording")]
    param (
        [string] $Title,
        [string] $OutputPath
    )

    if(!$script:SpectreRecordingType) {
        Write-Warning "No recording in progress"
        return
    }

    if(!$Title) {
        $Title = "Asciinema Recording"
    }

    # Get the recording
    switch ($script:SpectreRecordingType) {
        "asciinema" {
            $recording = $script:SpectreRecordingRecorder.GetAsciiCastRecording($Title)
        }
        "text" {
            $recording = [Spectre.Console.RecorderExtensions]::ExportText($script:SpectreRecordingRecorder)
        }
        "html" {
            $recording = [Spectre.Console.RecorderExtensions]::ExportHtml($script:SpectreRecordingRecorder)
        }
    }

    # Reset the console
    [Spectre.Console.AnsiConsole]::Console = $script:SpectreRecordingOriginalConsole
    $script:SpectreRecordingRecorder = $null
    $script:SpectreRecordingOriginalConsole = $null
    $script:SpectreRecordingType = $null
    
    # Return the output
    if ($OutputPath) {
        Set-Content -Path $OutputPath -Value $recording
        Write-Host "Saved recording to '$OutputPath'"
    } else {
        return $recording
    }
}


#endregion


#region PwshSpectreConsole/public/demo/Get-SpectreDemoColors.ps1


function Get-SpectreDemoColors {
    <#
    .SYNOPSIS
        Retrieves a list of Spectre Console colors and displays them with their corresponding markup.
        ![Spectre color demo](/colors.png)

    .DESCRIPTION
        The Get-SpectreDemoColors function retrieves a list of Spectre Console colors and displays them with their corresponding markup. 
        It also provides information on how to use the colors as parameters for commands or in Spectre Console markup.

    .EXAMPLE
        # **Example 1**  
        # This example demonstrates how to use Get-SpectreDemoColors to display a list of the built-in Spectre Console colors.
        Get-SpectreDemoColors
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/demo/get-spectredemocolors/')]
    [Reflection.AssemblyMetadata("title", "Get-SpectreDemoColors")]
    param ()

    Write-SpectreHost " "
    $width = Get-HostWidth
    $remainder = $width
    $colors = [Spectre.Console.Color] | Get-Member -Static -Type Properties | Select-Object -ExpandProperty Name
    $sortableColors = $colors | ForEach-Object {
        $color = [Spectre.Console.Color]::$_
        $hsv = Convert-RgbToHsv -Red $color.R -Green $color.G -Blue $color.B
        return [pscustomobject]@{
            Name = $_
            Color = $color
            Saturation = $hsv[1]
            ColorCategory = Get-ColorCategory -Hue $hsv[0] -Saturation $hsv[1] -Value $hsv[2]
            Lightness = Get-ColorLightness -Red $color.R -Green $color.G -Blue $color.B
        }
    }
    $colorCategories = $sortableColors | Group-Object ColorCategory
    $colorCategories | ForEach-Object {
        if ($_.Name -like "00 Grey*") {
            $sorted = $_.Group | Sort-Object -Property Lightness
        } else {
            $sorted = $_.Group | Sort-Object -Property Saturation -Descending
        }

        $sorted | ForEach-Object {
            $colorName = $_.Name
            $spaceRequired = $colorName.Length + 3
            $remainder -= $spaceRequired
            if ($remainder -le 0) {
                Write-SpectreHost "`n"
                $remainder = $width - $spaceRequired
            }

            $foreground = if (($_.Color.R + $_.Color.G + $_.Color.B) -gt 280) {
                "black"
            } else {
                "white"
            }

            Write-SpectreHost "[$foreground on #$($_.Color.ToHex())] $($_.Name) [/] " -NoNewline
        }
    }
    Write-SpectreHost "`n"
    Write-SpectreRule "Help"
    Write-SpectreHost " "

    Write-SpectreHost "The colors can be passed as the `"-Color`" parameter for most commands or used in Spectre Console markup like so:`n"
    Write-SpectreHost "  PS> [Yellow]Write-SpectreHost[/] [DeepSkyBlue1]`"$('I am [Red]colored text[/] using [Yellow1 on Turquoise4]Spectre markdown[/]!' | Get-SpectreEscapedText)`"[/]"
    Write-SpectreHost "  [white on grey19]I am [Red]colored text[/] using [Yellow1 on Turquoise4]Spectre markdown[/]!                                                          [/]"
    Write-SpectreHost "`nFor more markdown hints see [link]https://spectreconsole.net/markup[/]`n"
}


#endregion


#region PwshSpectreConsole/public/demo/Get-SpectreDemoEmoji.ps1


function Get-SpectreDemoEmoji {
    <#
    .SYNOPSIS
        Retrieves a collection of emojis available in Spectre Console.
        ![Example emojis](/emoji.png)

    .DESCRIPTION
        The Get-SpectreDemoEmoji function retrieves a collection of emojis available in Spectre Console. It displays the general emojis, faces, and provides information on how to use emojis in Spectre Console markup.

    .PARAMETER Count
        Limit the number of emoji returned. This is only really useful for generating the help docs.

    .EXAMPLE
        # **Example 1**  
        # This example demonstrates how to use Get-SpectreDemoEmoji to display a list of the built-in Spectre Console emojis.
        Get-SpectreDemoEmoji -Count 5

    .NOTES
        Emoji support is dependent on the operating system, terminal, and font support. For more information on Spectre Console markup and emojis, refer to the following links:
        - Spectre Console Markup: https://spectreconsole.net/markup
        - Spectre Console Emojis: https://spectreconsole.net/appendix/emojis
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/demo/get-spectredemoemoji/')]
    [Reflection.AssemblyMetadata("title", "Get-SpectreDemoEmoji")]
    param (
        [int] $Count
    )

    Write-SpectreHost " "
    Write-SpectreRule "`nEmoji"
    Write-SpectreHost " "
    
    $emojiCollection = [Spectre.Console.Emoji+Known] | Get-Member -Static -Type Properties | Select-Object -ExpandProperty Name
    if($Count) {
        $emojiCollection = $emojiCollection | Select-Object -First $Count
    }
    $faces = @()
    foreach ($emoji in $emojiCollection) {
        $id = ($emoji -creplace '([A-Z])', '_$1' -replace '^_', '').ToLower()
        if ($id -like "*face*") {
            $faces += $id
        } else {
            Write-SpectreHost ":${id}:`t$id"
        }
    }

    Write-SpectreHost " "
    if($faces) {
        Write-SpectreRule "Faces"
        Write-SpectreHost " "
        foreach ($face in $faces) {
            Write-SpectreHost ":${face}:`t$face"
        }
    }

    Write-SpectreHost " "
    Write-SpectreRule "Help"
    Write-SpectreHost " "
    Write-SpectreHost "The emoji can be used in Spectre Console markup like so:`n"
    # Apparently there is no way to escape emoji codes https://github.com/spectreconsole/spectre.console/issues/408
    Write-SpectreHost -NoNewline "  PS> [yellow]Write-SpectreHost[/] [DeepSkyBlue1]`"I am a :[/]"
    Write-SpectreHost -NoNewline "[DeepSkyBlue1]grinning_face: Spectre markdown emoji string :[/]"
    Write-SpectreHost "[DeepSkyBlue1]victory_hand: !`"[/]"
    Write-SpectreHost "  [white on grey19]I am a :grinning_face: Spectre markdown emoji string :victory_hand: !                                                [/]"
    Write-SpectreHost "`nEmoji support is dependent on OS, terminal & font support. For more markdown hints see [link]https://spectreconsole.net/markup[/] and for more emoji help see [link]https://spectreconsole.net/appendix/emojis[/]`n"
}


#endregion


#region PwshSpectreConsole/public/demo/Get-SpectreDemoFeatures.ps1


function Get-SpectreDemoFeatures {
    <#
    .SYNOPSIS
        Demonstrates the features of Spectre.Console.

    .DESCRIPTION
        This script demonstrates the features of Spectre.Console. It shows off the various colors, styles, and other features that Spectre.Console supports.

    .EXAMPLE
        # **Example 1**  
        # This example demonstrates how to use Get-SpectreDemoFeatures to display a list of the features of Spectre.Console as seen on the https://spectreconsole.net/ homepage.
        Get-SpectreDemoFeatures
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/demo/get-spectredemofeatures/')]
    [Reflection.AssemblyMetadata("title", "Get-SpectreDemoFeatures")]
    param ()

    $demoWidth = Get-HostWidth

    $title = Write-SpectreHost "[underline][yellow]PwshSpectreConsole[/][silver] Features[/][/]" -PassThru | Format-SpectreAligned -VerticalAlignment Middle
    $titleTable = Format-SpectreTable -Data @{
        Title = $title
    } -HideHeaders -Border None -Width $demoWidth
    
    $titleTable | Format-SpectrePadded -Top 1 -Left 0 -Bottom 0 -Right 0 | Out-SpectreHost
    
    # Colors
    $colors = @()
    $colors += Write-SpectreHost "[silver]✓[/] [red]2-bit color[/]" -PassThru
    $colors += Write-SpectreHost "[silver]✓[/] [green]3-bit color[/]" -PassThru
    $colors += Write-SpectreHost "[silver]✓[/] [blue]4-bit color[/]" -PassThru
    $colors += Write-SpectreHost "[silver]✓[/] [violet]8-bit color[/]" -PassThru
    $colors += Write-SpectreHost "[silver]✓[/] [yellow]Truecolor (16.7 million)[/]" -PassThru
    $colors += Write-SpectreHost "[silver]✓[/] [cyan]Automatic color conversion[/] " -PassThru
    $colorRows = $colors | Format-SpectreRows
    
    # Spectrum
    $spectrumRows = @()
    $brightnesses = 12
    $hues = $demoWidth - 52
    for ($b = 1; $b -le $brightnesses; $b+=2) {
        $line = ""
        for ($h = 0; $h -lt $hues; $h++) {
            $rgb1 = Convert-HslToRgb -Hue ($h * 360 / $hues) -Saturation 100 -Lightness (($b * 95) / $brightnesses)
            $color1 = [Spectre.Console.Color]::new($rgb1[0], $rgb1[1], $rgb1[2])
            $rgb2 = Convert-HslToRgb -Hue ($h * 360 / $hues) -Saturation 100 -Lightness ((($b + 1) * 95) / $brightnesses)
            $color2 = [Spectre.Console.Color]::new($rgb2[0], $rgb2[1], $rgb2[2])
            $line += "[#$($color2.ToHex()) on #$($color1.ToHex())]$([char]0x2584)[/]"
        }
        $spectrumRows += Write-SpectreHost $line -PassThru
    }
    $spectrumRows = $spectrumRows | Format-SpectreRows
    $colorColumns = Format-SpectreColumns -Data @(
        $colorRows,
        $spectrumRows
    )

    # Start the table creation
    $table = Format-SpectreTable -Data ([ordered]@{
        Feature = (Write-SpectreHost "[red]Colors[/]                         " -PassThru) # Force column width to be wide enough for the longest line
        Demo = $colorColumns
    }) -HideHeaders -Border None -Width $demoWidth
    $table = Add-SpectreTableRow -Table $table -Columns @("", "")

    # OS
    $os = Write-SpectreHost "[green]Windows[/] [blue]macOS[/] [yellow]Linux[/]" -PassThru
    $table = Add-SpectreTableRow -Table $table -Columns @((Write-SpectreHost "[red]OS[/]" -PassThru), $os)
    $table = Add-SpectreTableRow -Table $table -Columns @("", "")

    # Styles
    $styles = Write-SpectreHost "[silver]All ansi styles[/] [bold]bold[/], [dim]dim[/], [italic]italic[/], [underline]underline[/], [strikethrough]strikethrough[/], [reverse]reverse[/], and even [rapidblink]blink[/]" -PassThru
    $table = Add-SpectreTableRow -Table $table -Columns @((Write-SpectreHost "[red]Styles[/]" -PassThru), $styles)
    $table = Add-SpectreTableRow -Table $table -Columns @("", "")

    # Wrap
    $wrapRows = @()
    $wrapRows += Write-SpectreHost "[silver]Word wrap text. Justify[/] [green]left[/], [yellow]center[/], or [blue]right[/]" -PassThru
    $wrapRows += ""
    $textToWrap = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Pellentesque nec blandit quam. Vestibulum sed turpis eget metus feugiat imperdiet. Quisque tempor cursus nibh vitae maximus."
    $wrapRows += New-SpectreGridRow -Data @(
        (Write-SpectreHost "[green]$textToWrap[/]" -PassThru | Format-SpectreAligned -HorizontalAlignment Left),
        (Write-SpectreHost "[yellow]$textToWrap[/]" -PassThru | Format-SpectreAligned -HorizontalAlignment Center),
        (Write-SpectreHost "[blue]$textToWrap[/]" -PassThru | Format-SpectreAligned -HorizontalAlignment Right)
    ) | Format-SpectreGrid -Width $demoWidth
    $wrapRows = $wrapRows | Format-SpectreRows
    $table = Add-SpectreTableRow -Table $table -Columns @((Write-SpectreHost "[red]Wrap[/]" -PassThru), $wrapRows)
    $table = Add-SpectreTableRow -Table $table -Columns @("", "")

    # Markup
    $markup = Write-SpectreHost "[violet]Spectre.Console[/] supports a simple bbcode like [bold]markup[/] for [yellow]color[/], [underline]style[/], and emoji! :thumbs_up: :red_apple: :ant: :bear: :baguette_bread: :bus:" -PassThru

    $table = Add-SpectreTableRow -Table $table -Columns @((Write-SpectreHost "[red]Markup[/]" -PassThru), $markup)
    $table = Add-SpectreTableRow -Table $table -Columns @("", "")

    # Tables and trees
    $embeddedTable = @(
        ([ordered]@{
            Foo = "Baz  "
            Bar = @(
                (Write-SpectreHost "`n[grey]Overview[/]" -PassThru),
                (Write-SpectreRule -Color Silver -PassThru),
                (@{
                    Value = "📁 src"
                    Children = @(
                        @{
                            Value = "📁 foo"
                            Children = @(
                                @{
                                    Value = "📄 bar.cs"
                                }
                            )
                        },
                        @{
                            Value = "📁 baz"
                            Children = @(
                                @{
                                    Value = "📁 qux"
                                    Children = @(
                                        @{
                                            Value = "📄 corgi.txt"
                                        }
                                    )
                                }
                            )
                        },
                        @{
                            Value = "📄 waldo.xml"
                        }
                    )
                } | Format-SpectreTree),
                (Write-SpectreRule -Color Silver -PassThru),
                (Write-SpectreHost "[grey]3 Files, 225 KiB[/]" -PassThru)
            ) | Format-SpectreRows
        }),
        ([ordered]@{
            Foo = ""
            Bar = ""
        })
        ([ordered]@{
            Foo = "Qux"
            Bar = "Corgi"
        })
     ) | Format-SpectreTable -Color Yellow -Width ($demoWidth - 22)
    $table = Add-SpectreTableRow -Table $table -Columns @((Write-SpectreHost "[red]Tables and Trees[/]" -PassThru), $embeddedTable)

    # Charts
    $breakdownChart = @(
        (New-SpectreChartItem -Label "PowerShell" -Value 70.2 -Color Blue),
        (New-SpectreChartItem -Label "MDX" -Value 24.7 -Color Red),
        (New-SpectreChartItem -Label "C#" -Value 3 -Color Green),
        (New-SpectreChartItem -Label "Astro" -Value 3 -Color Blue)
    ) | Format-SpectreBreakdownChart -ShowPercentage -Width ([int](($demoWidth - 30) / 2)) | Format-SpectrePanel -Border Square -Color Grey -Height 5

    $barChart = @(
        (New-SpectreChartItem -Label "Apple" -Value 32 -Color Green),
        (New-SpectreChartItem -Label "Oranges" -Value 13 -Color Orange1),
        (New-SpectreChartItem -Label "Bananas" -Value 22 -Color Yellow)
    ) | Format-SpectreBarChart -Width ([int](($demoWidth - 30) / 2) - 1) | Format-SpectrePanel -Border Square -Color Grey

    $chartColumns = Format-SpectreColumns -Data @(
        $breakdownChart,
        $barChart
    )

    $table = Add-SpectreTableRow -Table $table -Columns @((Write-SpectreHost "[red]Charts[/]" -PassThru), $chartColumns)
    $table = Add-SpectreTableRow -Table $table -Columns @("", "")

    # Exceptions
    $exceptionData = $null
    try {
        Get-ChildItem -BadParam -ErrorAction Stop
    } catch {
        $exceptionData = $_ | Format-SpectreException -ExceptionFormat ShortenEverything
    }
    $table = Add-SpectreTableRow -Table $table -Columns @((Write-SpectreHost "[red]Exceptions[/]" -PassThru), $exceptionData)
    $table = Add-SpectreTableRow -Table $table -Columns @("", "")

    # Much more
    $more = @(
        (Write-SpectreHost "Tables, Grids, Trees, Progress bars, Status, Bar charts, Calendars, Figlet, Images," -PassThru),
        (Write-SpectreHost "Text prompts, List boxes, Separators, Pretty exceptions, Canvas" -PassThru)
    ) | Format-SpectreRows
    $table = Add-SpectreTableRow -Table $table -Columns @((Write-SpectreHost "[red]+ Much More![/]" -PassThru), $more)
    $table = Add-SpectreTableRow -Table $table -Columns @("", "")

    $table | Format-SpectrePadded -Top 1 -Left 0 -Bottom 0 -Right 0 | Out-SpectreHost

    Write-SpectreHost " "
}


#endregion


#region PwshSpectreConsole/public/demo/Open-PwshSpectreConsoleHelp.ps1


function Open-PwshSpectreConsoleHelp {
    <#
        .SYNOPSIS
            Opens the help page for PwshSpectreConsole in the default browser.
        .DESCRIPTION
            This function opens the help page for PwshSpectreConsole in the default browser.
        .EXAMPLE
            # **Example 1**
            # Open the help page for PwshSpectreConsole in the default browser.
            Open-PwshSpectreConsoleHelp
        .LINK
            https://pwshspectreconsole.com/guides/get-started/
    #>
    [Reflection.AssemblyMetadata("title", "Open-PwshSpectreConsoleHelp")]
    param()

    $online = "https://pwshspectreconsole.com/guides/get-started/"
    
    Write-SpectreHost "[Grey69]Opening the [white link=$online]online help page[/] for PwshSpectreConsole in your default browser...[/]"

    try {
        if ($IsWindows) {
            Start-Process $online -ErrorAction Stop -Wait
            return
        } elseif ($IsLinux -and (Get-Command -Name "xdg-open" -ErrorAction SilentlyContinue)) {
            Start-Process "xdg-open" -ArgumentList $online -ErrorAction Stop
            return
        } elseif ($IsMacOS) {
            Start-Process "open" -ArgumentList $online -ErrorAction Stop -Wait
            return
        }   
    } catch {
        Write-SpectreHost "[DarkOrange]Unable to open your browser :crying_face:[/]"
    }

    Write-SpectreHost "[DarkOrange]View [white link]$online[/] in your browser to view online help for this module.[/]"
}


#endregion


#region PwshSpectreConsole/public/demo/Start-SpectreDemo.ps1


function Write-SpectreExample {
    param (
        [Parameter(ValueFromPipeline)]
        [string] $Codeblock,
        [string] $Title,
        [string] $Description,
        [switch] $HideHeader,
        [switch] $NoNewline
    )
    if ($host.UI.RawUI.WindowSize.Width -lt 120) {
        Write-SpectreFigletText "Pwsh + Spectre!"
    } else {
        Write-SpectreFigletText "Welcome to PwshSpectreConsole!"
    }
    Write-Host ""

    Write-SpectreRule $Title -Color ([Spectre.Console.Color]::SteelBlue1)
    Write-SpectreHost "`n$Description"
    if (!$HideHeader) {
        Write-CodeblockHeader
    }
    $Codeblock | Write-Codeblock -SyntaxHighlight -ShowLineNumbers
    if (!$NoNewline) {
        Write-Host ""
    }
}

function Start-SpectreDemo {
    <#
    .SYNOPSIS
    Runs a demo of the PwshSpectreConsole module.

    .DESCRIPTION
    This function runs a demo of the PwshSpectreConsole module, showcasing some of its features.  
    It displays various examples of Spectre.Console functionality wrapped in PowerShell functions, such as text entry, select lists, multi-select lists, and panels.
    ![Spectre demo animation](/demo.gif)

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to run the PwshSpectreConsole demo.
    Start-SpectreDemo
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/demo/start-spectredemo/')]
    [Reflection.AssemblyMetadata("title", "Start-SpectreDemo")]
    param()

    Clear-Host

    if ($host.UI.RawUI.WindowSize.Width -lt 120) {
        Write-SpectreFigletText "Pwsh + Spectre!"
    } else {
        Write-SpectreFigletText "Welcome to PwshSpectreConsole!"
    }
    Write-Host ""

    Write-SpectreRule "PwshSpectreConsole Intro" -Color ([Spectre.Console.Color]::SteelBlue1)
    Write-SpectreHost "`nPwshSpectreConsole is a wrapper for the awesome Spectre.Console library. The internals of Spectre Console have not just been exposed to PowerShell but have wrapped them in a way that makes them work better in the PowerShell ecosystem."
    Write-SpectreHost "`nSpectre Console is mostly an async library and it leans heavily on types and extension methods in C# which are very verbose to work with in PowerShell so this module hides away some of the complexity."
    Write-SpectreHost "`nThe module exposes all core functionality of Spectre.Console but not all configuration options may be available. Feel free to open an issue on the Github repo if you would like to see something added."
    Write-Host ""
    if (![Spectre.Console.AnsiConsole]::Console.Profile.Capabilities.Unicode) {
        Write-Warning "To enable all features of Spectre.Console you need to enable Unicode support in your PowerShell profile by adding the following to your profile at $PROFILE. See https://spectreconsole.net/best-practices for more info.`n`n`$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding`n"
    }

    Read-SpectrePause -NoNewline
    
    Clear-Host

    $example = @'
$name = Read-SpectreText "What's your [blue]name[/]?" -AllowEmpty
'@
    $example | Write-SpectreExample -Title "Text Entry" -Description "Text entry is essential for user input and interaction in a terminal application. It allows users to enter commands, input data, or provide search queries, giving them the ability to interact with the application and perform tasks. The built-in PowerShell Read-Host has some additional functionality like auto-complete and history that the Spectre text entry doesn't have so Read-Host is usually a better option for text entry in your scripts."
    $example | Invoke-Expression
    Clear-Host

    $example = @'
$answer = Read-SpectreConfirm -Prompt "Do you like cute animals?" -DefaultAnswer "y"
'@
    $example | Write-SpectreExample -Title "Confirmation" -Description "Confirmation prompts are used to confirm an action or decision before it is executed. They help prevent users from making mistakes or taking actions they did not intend to, reducing the chances of errors and improving the overall user experience."
    $example | Invoke-Expression
    Clear-Host

    $example = @'
$choices = @("Pizza", "Sushi", "Tacos", "Pad Thai", "Lobster", "Falafel", "Chicken Parmesan", "Ramen", "Fish and Chips", "Biryani", "Croissants", "Enchiladas", "Shepherd's Pie", "Gyoza", "Fajitas", "Samosas", "Bruschetta", "Paella", "Hamburger", "Poutine", "Ceviche")

$food = Read-SpectreSelection `
            -Title "What's your favourite [blue]food[/]?" `
            -Choices $choices
'@
    $example | Write-SpectreExample -Title "Select Lists" -Description "Select lists are helpful for presenting multiple options to the user in an organized manner. They enable users to choose one option from a list, simplifying decision-making and input tasks and reducing the chances of errors. The list will also paginate if there are too many options to show all at once."
    $example | Invoke-Expression
    Clear-Host

    $example = @'
$choices = @(
    @{ Name = "RGB"; Choices = @("red", "green", "blue") },
    @{ Name = "CMYK"; Choices = @("cyan", "magenta", "yellow", "black") }
)

$colors = Read-SpectreMultiSelectionGrouped `
              -Title "What's your favourite [blue]color[/]?" `
              -Choices $choices `
              -AllowEmpty
'@
    $example | Write-SpectreExample -Title "Multi-Select Lists" -Description "Multi-select lists allow users to choose multiple options from a list. This feature is useful when users need to perform operations on multiple items at once, such as selecting multiple files to delete or copy. The multi-select lists also allow categorizing items so you can select the whole category at once."
    $example | Invoke-Expression
    Clear-Host

    $example = @'
$message = "Hi $name, nice to meet you :waving_hand:`n"
$message += "Your favourite food is $food :fork_and_knife:`n"
$message += "And your favourite colors are:`n"
if($colors) {
    foreach($color in $colors) {
        $message += " - [$color]$color[/]`n"
    }
} else {
    $message += "Nothing, you didn't select any colors :crying_face:"
}
$message += "Nice! :rainbow:"

$message | Format-SpectrePanel -Title "Output"
'@
    $example | Write-SpectreExample -Title "Panels" -Description "Panels are used to separate and organize different sections or groups of information within a terminal application. They help keep the interface clean and structured, making it easier for users to navigate and understand the application."
    Invoke-Expression $example

    Read-SpectrePause
    Clear-Host

    $example = @'
Get-Process | Select-Object -First 10 -Property Id, Name, Handles | Format-SpectreTable
'@
    $example | Write-SpectreExample -Title "Tables" -Description "Tables are an effective way to display structured data in a terminal application. They provide a clear and organized representation of data, making it easier for users to understand, compare, and analyze the information. The tables in Spectre Console are not as feature rich as the built-in PowerShell Format-Table but they can have more visual impact."
    Invoke-Expression $example

    Read-SpectrePause
    Clear-Host

    $example = @'
@{
    Value = "Root"
    Children = @(
        @{
            Value = "First Child"
            Children = @(
                @{ Value = "With" },
                @{ Value = "Loads" },
                @{ Value = "More" },
                @{ Value = "Nested"; Children = @( @{ Value = "Children" } ) }
            )
        },
        @{ Value = "Second Child" }
    )
} | Format-SpectreTree
'@
    $example | Write-SpectreExample -Title "Tree Diagrams" -Description "Tree diagrams help visualize hierarchical relationships between different elements in a dataset. They are particularly useful in applications dealing with file systems, organizational structures, or nested data, providing an intuitive representation of the structure."
    Invoke-Expression $example

    Read-SpectrePause
    Clear-Host

    $example = @'
$(
    @{
        Label = "Apple"
        Value = 12
        Color = [Spectre.Console.Color]::Green
    },
    @{
        Label = "Orange"
        Value = 54
        Color = [Spectre.Console.Color]::Orange1
    },
    @{
        Label = "Strawberry"
        Value = 51
        Color = [Spectre.Console.Color]::Red
    },
    @{
        Label = "Banana"
        Value = 33
        Color = [Spectre.Console.Color]::Yellow
    }
) | Format-SpectreBarChart
'@
    $example | Write-SpectreExample -Title "Bar Charts" -Description "Bar charts are a powerful way to visualize data comparisons in a terminal application. They can represent various data types, such as categorical or numerical data, making it easier for users to identify trends, patterns, and differences between data points."
    Invoke-Expression $example

    Read-SpectrePause
    Clear-Host

    $example = @'
$(
    @{
        Label = "Apple"
        Value = 12
        Color = [Spectre.Console.Color]::Green
    },
    @{
        Label = "Strawberry"
        Value = 15
        Color = [Spectre.Console.Color]::Red
    },
    @{
        Label = "Orange"
        Value = 54
        Color = [Spectre.Console.Color]::Orange1
    },
    @{
        Label = "Plum"
        Value = 75
        Color = [Spectre.Console.Color]::Fuchsia
    }
) | Format-SpectreBreakdownChart
'@
    $example | Write-SpectreExample -Title "Breakdown Charts" -Description "Like a pie chart but horizontal, breakdown charts can be used to show the proportions of a total that components make up."
    Invoke-Expression $example
    Read-SpectrePause
    Clear-Host

    $example = @'
Get-Module PwshSpectreConsole | Select-Object PrivateData | Format-SpectreJson
'@
    $example | Write-SpectreExample -Title "Json Data" -Description "Spectre Console can format JSON with syntax highlighting thanks to https://github.com/trackd"
    Invoke-Expression $example
    Read-SpectrePause
    Clear-Host

    $example = @'
Invoke-SpectreCommandWithStatus -Spinner "Dots2" -Title "Showing a spinner..." -ScriptBlock {
    # Write updates to the host using Write-SpectreHost
    Start-Sleep -Seconds 1
    Write-SpectreHost "`n[grey]LOG:[/] Doing some work      "
    Start-Sleep -Seconds 1
    Write-SpectreHost "`n[grey]LOG:[/] Doing some more work "
    Start-Sleep -Seconds 1
    Write-SpectreHost "`n[grey]LOG:[/] Done                 "
    Start-Sleep -Seconds 1
}
'@
    $example | Write-SpectreExample -Title "Progress Spinners" -Description "Progress spinners provide visual feedback to users when an operation or task is in progress. They help indicate that the application is working on a request, preventing users from becoming frustrated or assuming the application has stalled."
    Invoke-Expression $example

    Read-SpectrePause
    Clear-Host

    $example = @'
Invoke-SpectreCommandWithProgress -ScriptBlock {
    param (
        $ctx
    )
    $task1 = $ctx.AddTask("A 4-stage process")
    Start-Sleep -Seconds 1
    $task1.Increment(25)
    Start-Sleep -Seconds 1
    $task1.Increment(25)
    Start-Sleep -Seconds 1
    $task1.Increment(25)
    Start-Sleep -Seconds 1
    $task1.Increment(25)
    Start-Sleep -Seconds 1
}
'@
    $example | Write-SpectreExample -NoNewline -Title "Progress Bars" -Description "Progress bars give users a visual indication of the progress of a specific task or operation. They show the percentage of completion, helping users understand how much work remains and providing a sense of time estimation for the task."
    Invoke-Expression $example

    Read-SpectrePause -NoNewline
    Clear-Host

    $example = @'
Invoke-SpectreCommandWithProgress -ScriptBlock {
    param ( $ctx )

    $jobs = @()
    $jobs += Add-SpectreJob -Context $ctx -JobName "Drawing a picture" -Job (
        Start-Job {
            $progress = 0
            while($progress -lt 100) {
                $progress += 1.5
                Write-Progress -Activity "Processing" -PercentComplete $progress
                Start-Sleep -Milliseconds 50
            }
        }
    )
    $jobs += Add-SpectreJob -Context $ctx -JobName "Driving a car" -Job (
        Start-Job {
            $progress = 0
            while($progress -lt 100) {
                $progress += 0.9
                Write-Progress -Activity "Processing" -PercentComplete $progress
                Start-Sleep -Milliseconds 50
            }
        }
    )

    Wait-SpectreJobs -Context $ctx -Jobs $jobs
}
'@
    $example | Write-SpectreExample -NoNewline -Title "Parallel Progress Bars" -Description "Parallel progress bars are used to display the progress of multiple tasks or operations simultaneously. They are useful in applications that perform several tasks concurrently, allowing users to monitor the status of each task individually."
    Invoke-Expression $example

    Read-SpectrePause -NoNewline
    Clear-Host

    $example = @'
Invoke-SpectreCommandWithProgress -ScriptBlock {
    param (
        $ctx
    )
    $task1 = $ctx.AddTask("Doing something")
    $task1.IsIndeterminate = $true
    Start-Sleep -Seconds 10
    $task1.IsIndeterminate = $false
    $task1.Value = 100
    $task1.StopTask()
}
'@
    $example | Write-SpectreExample -NoNewline -Title "Indeterminate Progress Bars" -Description "Indeterminate progress bars are used when the duration of a task or operation is unknown or cannot be accurately estimated. They provide a visual indication that work is being done, even if the exact progress cannot be determined, reassuring users that the application is still functioning. You could also use spinners to portray this information but sometimes you want to be consistent if you're already using progress bars for other tasks."
    Invoke-Expression $example

    Read-SpectrePause -NoNewline
    Clear-Host

    $example = @"
Get-SpectreImage "$PSScriptRoot\smiley.png" -Width 40
"@
    $example | Write-SpectreExample -Title "View Images" -Description "Images can be rendered in the terminal, given a path to an image Spectre Console will downsample the image to a resolution that will fit within the terminal width or you can choose your own width setting."
    Invoke-Expression $example

    Read-SpectrePause
    Clear-Host

    if ($host.UI.RawUI.WindowSize.Width -lt 120) {
        Write-SpectreFigletText "Pwsh + Spectre!"
    } else {
        Write-SpectreFigletText "Welcome to PwshSpectreConsole!"
    }
    Write-Host ""

    Write-SpectreRule "PwshSpectreConsole Outro" -Color ([Spectre.Console.Color]::SteelBlue1)

    Get-SpectreDemoFeatures

    @(
        (Write-SpectreHost "Thanks for checking out the PwshSpectreConsole demo!" -PassThru | Format-SpectrePadded -Top 1 -Left 0 -Right 0 -Bottom 1),
        (Write-SpectreHost "There are more examples and documentation at [blue]https://pwshspectreconsole.com/[/]" -PassThru),
        (Write-SpectreHost "You can also check out the original dotnet library documentation at [blue]https://spectreconsole.net/[/]" -PassThru),
        (Write-SpectreHost "Have fun :waving_hand:" -PassThru | Format-SpectrePadded -Top 1 -Left 0 -Right 0 -Bottom 1)
    ) | Format-SpectreRows
}


#endregion


#region PwshSpectreConsole/public/formatting/Add-SpectreTableRow.ps1


function Add-SpectreTableRow {
    <#
    .SYNOPSIS
    Adds a row to a Spectre Console table.

    .DESCRIPTION
    Adds a row to a Spectre Console table. The number of columns in the row must match the number of columns in the table.

    .PARAMETER Table
    The table to which the row will be added.

    .PARAMETER Columns
    An array of renderable items containing the data to be displayed in the columns of this row.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to add a row to an existing Spectre Console table.
    $data = @(
        [pscustomobject]@{Name="John"; Age=25; City="New York"},
        [pscustomobject]@{Name="Jane"; Age=30; City="Los Angeles"}
    )
    $table = Format-SpectreTable -Data $data
    $table | Out-SpectreHost

    $table = Add-SpectreTableRow -Table $table -Columns "Shaun", 99, "Wellington"
    $table | Out-SpectreHost
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/add-spectretablerow/')]
    [Reflection.AssemblyMetadata("title", "Add-SpectreTableRow")]
    param (
        [Parameter(Mandatory)]
        [Spectre.Console.Table] $Table,
        [Parameter(ValueFromPipeline)]
        [array] $Columns
    )

    if ($table.Columns.Count -ne $Columns.Count) {
        throw "The number of columns $($Columns.Count) in the row must match the number of columns in the table $($table.Columns.Count)"
    }

    $renderableColumns = $Columns | Foreach-Object { $_ | ConvertTo-Renderable }
    $table = [Spectre.Console.TableExtensions]::AddRow($Table, [Spectre.Console.Rendering.Renderable[]]$renderableColumns)

    return $table
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectreAligned.ps1


function Format-SpectreAligned {
    <#
    .SYNOPSIS
    Wraps a renderable object in a Spectre Console Aligned object.

    .DESCRIPTION
    This wraps a renderable object in a Spectre Console Aligned object. This allows you to align the object horizontally and vertically within a space. Aligned objects are always expanded so they take up all available horizontal space.  

    .PARAMETER Data
    The renderable object to align.

    .PARAMETER HorizontalAlignment
    The horizontal alignment of the object.

    .PARAMETER VerticalAlignment
    The vertical alignment of the object.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to align a string to the right inside a panel.
    "hello right hand side" | Format-SpectreAligned -HorizontalAlignment Right -VerticalAlignment Middle | Format-SpectrePanel -Expand -Height 9
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectrealigned/')]
    [Reflection.AssemblyMetadata("title", "Format-SpectreAligned")]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [RenderableTransformationAttribute()]
        [object] $Data,
        [ValidateSet([SpectreConsoleHorizontalAlignment], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string] $HorizontalAlignment = "Center",
        [ValidateSet([SpectreConsoleVerticalAlignment], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string] $VerticalAlignment = "Middle"
    )

    $aligned = [Spectre.Console.Align]::new(
        $Data,
        [Spectre.Console.HorizontalAlignment]::$HorizontalAlignment,
        [Spectre.Console.VerticalAlignment]::$VerticalAlignment
    )
    
    return $aligned
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectreBarChart.ps1


function Format-SpectreBarChart {
    <#
    .SYNOPSIS
    Formats and displays a bar chart using the Spectre Console module.

    .DESCRIPTION
    This function takes an array of data and displays it as a bar chart using the Spectre Console module. The chart can be customized with a title and width.  
    See https://spectreconsole.net/widgets/barchart for more information.

    .PARAMETER Data
    An array of objects containing the data to be displayed in the chart. Each object should have a Label, Value, and Color property.

    .PARAMETER Label
    The title to be displayed above the chart.

    .PARAMETER Width
    The width of the chart in characters.

    .PARAMETER HideValues
    Hides the values from being displayed on the chart.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to display a bar chart of various data points.
    $data = @()

    $data += New-SpectreChartItem -Label "Apples" -Value 10 -Color "Green"
    $data += New-SpectreChartItem -Label "Oranges" -Value 5 -Color "DarkOrange"
    $data += New-SpectreChartItem -Label "Bananas" -Value 2.2 -Color "#FFFF00"
    
    Format-SpectreBarChart -Data $data -Label "Fruit Sales" -Width 50
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectrebarchart/')]
    [Reflection.AssemblyMetadata("title", "Format-SpectreBarChart")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [ChartItemTransformationAttribute()]
        [object] $Data,
        [Alias("Title")]
        [String] $Label,
        [ValidateScript({ $_ -gt 0 -and $_ -le (Get-HostWidth) }, ErrorMessage = "Value '{0}' is invalid. Cannot be negative or exceed console width.")]
        [int] $Width = (Get-HostWidth),
        [switch] $HideValues
    )
    begin {
        $barChart = [Spectre.Console.BarChart]::new()
        if ($Label) {
            $barChart.Label = $Label
        }
        if ($HideValues) {
            $barChart.ShowValues = $false
        }
        $barChart.Width = $Width
    }
    process {
        if ($Data -is [array]) {
            foreach ($dataItem in $Data) {
                $barChart = [Spectre.Console.BarChartExtensions]::AddItem($barChart, $dataItem.Label, $dataItem.Value, ($dataItem.Color | Convert-ToSpectreColor))
            }
        } else {
            $barChart = [Spectre.Console.BarChartExtensions]::AddItem($barChart, $Data.Label, $Data.Value, ($Data.Color | Convert-ToSpectreColor))
        }
    }
    end {
        return $barChart
    }
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectreBreakdownChart.ps1


function Format-SpectreBreakdownChart {
    <#
    .SYNOPSIS
    Formats data into a breakdown chart.

    .DESCRIPTION
    This function takes an array of data and formats it into a breakdown chart using BreakdownChart. The chart can be customized with a specified width and color.  
    See https://spectreconsole.net/widgets/breakdownchart for more information.

    .PARAMETER Data
    An array of data to be formatted into a breakdown chart.

    .PARAMETER Width
    The width of the chart. Defaults to the width of the console.

    .PARAMETER HideTags
    Hides the tags on the chart.

    .PARAMETER HideTagValues
    Hides the tag values on the chart.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to display a breakdown chart of various data points.
    $data = @()

    $data += New-SpectreChartItem -Label "Apples" -Value 10 -Color "Green"
    $data += New-SpectreChartItem -Label "Oranges" -Value 5 -Color "Gold1"
    $data += New-SpectreChartItem -Label "Bananas" -Value 2.2 -Color "#FFFF00"

    Format-SpectreBreakdownChart -Data $data -Width 50
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectrebreakdownchart/')]
    [Reflection.AssemblyMetadata("title", "Format-SpectreBreakdownChart")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [ChartItemTransformationAttribute()]
        [object] $Data,
        [ValidateScript({ $_ -gt 0 -and $_ -le (Get-HostWidth) }, ErrorMessage = "Value '{0}' is invalid. Cannot be negative or exceed console width.")]
        [int]$Width = (Get-HostWidth),
        [switch]$HideTags,
        [switch]$HideTagValues,
        [switch]$ShowPercentage
    )
    begin {
        $chart = [Spectre.Console.BreakdownChart]::new()
        $chart.Width = $Width
        if ($HideTags) {
            $chart.ShowTags = $false
        }
        if ($HideTagValues) {
            $chart.ShowTagValues = $false
        }
        if ($ShowPercentage) {
            $chart = [Spectre.Console.BreakdownChartExtensions]::ShowPercentage($chart)
        }
    }
    process {
        if ($Data -is [array]) {
            foreach ($dataItem in $Data) {
                [Spectre.Console.BreakdownChartExtensions]::AddItem($chart, $dataItem.Label, $dataItem.Value, ($dataItem.Color | Convert-ToSpectreColor)) | Out-Null
            }
        } else {
            [Spectre.Console.BreakdownChartExtensions]::AddItem($chart, $Data.Label, $Data.Value, ($Data.Color | Convert-ToSpectreColor)) | Out-Null
        }
    }
    end {
        return $chart
    }
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectreColumns.ps1


function Format-SpectreColumns {
    <#
    .SYNOPSIS
    Renders a collection of renderables in columns to the console.

    .DESCRIPTION
    This function creates a spectre columns widget that renders a collection of renderables in autosized columns to the console.  
    Columns can contain renderable items.  
    See https://spectreconsole.net/widgets/columns for more information.

    .PARAMETER Data
    An array of objects containing the data to be displayed in the columns.

    .PARAMETER Padding
    The padding to apply to the columns.

    .PARAMETER Expand
    A switch to expand the columns to fill the available space.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to display a collection of strings in columns.
    @("lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit,", "sed", "do", "eiusmod",
      "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua.", "Ut", "enim", "ad", "minim",
      "veniam,", "quis", "nostrud", "exercitation", "ullamco", "laboris", "nisi", "ut", "aliquip", "ex", "ea",
      "commodo", "consequat", "duis", "aute", "irure", "dolor", "in", "reprehenderit", "in", "voluptate", "velit",
      "esse", "cillum", "dolore", "eu", "fugiat", "nulla", "pariatur", "excepteur", "sint", "occaecat",
      "cupidatat", "non", "proident", "sunt", "in", "culpa") | Foreach-Object { $_ } | Format-SpectreColumns

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to display a collection of panels that are expanded but with normal sized columns.
    @("left", "middle", "right") | Foreach-Object { $_ | Format-SpectrePanel -Expand } | Format-SpectreColumns

    .EXAMPLE
    # **Example 3**  
    # This example demonstrates how to display a collection of panels that are expanded and with expanded columns so it takes up the console width.
    @("left", "middle", "right") | Foreach-Object { $_ | Format-SpectrePanel -Expand } | Format-SpectreColumns -Expand
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectrecolumns/')]
    [Reflection.AssemblyMetadata("title", "Format-SpectreColumns")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [object] $Data,
        [int] $Padding = 1,
        [switch] $Expand
    )
    begin {
        $columnItems = @()
    }
    process {
        if ($Data -is [array]) {
            foreach ($dataItem in $Data) {
                if ($dataItem -is [Spectre.Console.Rendering.Renderable]) {
                    $columnItems += $dataItem
                } else {
                    $columnItems += $dataItem | ConvertTo-Renderable
                }
            }
        } else {
            if ($Data -is [Spectre.Console.Rendering.Renderable]) {
                $columnItems += $Data
            } else {
                $columnItems += $Data | ConvertTo-Renderable
            }
        }
    }
    end {
        $columns = [Spectre.Console.Columns]::new($columnItems)
        $columns.Expand = $Expand
        if ($Padding -ne 1) {
            $columns.Padding = [Spectre.Console.Padding]::new($Padding, $Padding, $Padding, $Padding)
        }

        return $columns
    }
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectreException.ps1


function Format-SpectreException {
    <#
    .SYNOPSIS
    Formats an error record/exception into a Spectre Console Exception which supports syntax highlighting.

    .DESCRIPTION
    Formats an error record/exception into a Spectre Console Exception which supports syntax highlighting.  
    See https://spectreconsole.net/exceptions for more information.

    .PARAMETER Exception
    The error/exception object to format.

    .PARAMETER ExceptionFormat
    The format to use when rendering the exception. The default value is "Default".

    .PARAMETER ExceptionStyle
    The style to use when rendering the exception provided as a hashtable.
    You can provide a partial hashtable to override only specific styles, the rest will use defaults.
    e.g. 
    ```
    @{
        Message        = "red"
        Exception      = "white"
        Method         = "yellow"
        ParameterType  = "blue"
        ParameterName  = "silver"
        Parenthesis    = "silver"
        Path           = "Yellow"
        LineNumber     = "blue"
        Dimmed         = "grey"
        NonEmphasized  = "silver"
    }
    ```

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to format an exception into a Spectre Console Exception with syntax highlighting.
    try {
        Get-ChildItem -BadParam -ErrorAction Stop
    } catch {
        $_ | Format-SpectreException -ExceptionFormat ShortenEverything
    }

    .EXAMPLE
    # **Example 2**
    # This example uses custom formatting for the exception.
    try {
        Get-ChildItem -BadParam -ErrorAction Stop
    } catch {
        $_ | Format-SpectreException -ExceptionStyle @{
            Message        = "#00ff00"
            Exception      = "white"
            Method         = "#ff0000 on orange1"
            ParameterType  = "blue"
            ParameterName  = "silver"
            Parenthesis    = "silver"
            Path           = "Yellow"
            LineNumber     = "blue"
            Dimmed         = "grey"
            NonEmphasized  = "silver"
        }
    }
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectreexception/')]
    [Reflection.AssemblyMetadata("title", "Format-SpectreException")]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [object] $Exception,
        [ValidateSet([SpectreConsoleExceptionFormats], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string] $ExceptionFormat = "Default",
        [ColorThemeTransformationAttribute()]
        [hashtable] $ExceptionStyle = @{}
    )

    $defaultExceptionStyle = @{
        Message        = [Spectre.Console.Style]::Parse("Red")
        Exception      = [Spectre.Console.Style]::Parse("White")
        Method         = [Spectre.Console.Style]::new([Spectre.Console.Color]::Pink3)
        ParameterType  = [Spectre.Console.Style]::Parse("Grey69")
        ParameterName  = [Spectre.Console.Style]::new($script:DefaultValueColor)
        Parenthesis    = [Spectre.Console.Style]::new($script:DefaultValueColor)
        Path           = [Spectre.Console.Style]::new([Spectre.Console.Color]::Pink3)
        LineNumber     = [Spectre.Console.Style]::Parse("Blue")
        Dimmed         = [Spectre.Console.Style]::Parse("Grey")
        NonEmphasized  = [Spectre.Console.Style]::new($script:DefaultValueColor)
    }
    Merge-HashtableDefaults -UserStyle $ExceptionStyle -DefaultStyle $defaultExceptionStyle

    if ($Exception -is [System.Management.Automation.ErrorRecord]) {
        $exceptionObject = $Exception.Exception
    } elseif ($Exception -is [System.Exception]) {
        $exceptionObject = $Exception
    } else {
        throw "Invalid exception object type $($Exception.GetType().FullName). Must be of type [System.Management.Automation.ErrorRecord] or [System.Exception]."
    }

    $exceptionSettings = [Spectre.Console.ExceptionSettings]::new()
    $exceptionSettings.Format = [Spectre.Console.ExceptionFormats]::$ExceptionFormat
    $exceptionSettings.Style = [Spectre.Console.ExceptionStyle]::new()
    $exceptionSettings.Style.Message = $ExceptionStyle.Message
    $exceptionSettings.Style.Exception = $ExceptionStyle.Exception
    $exceptionSettings.Style.Method = $ExceptionStyle.Method
    $exceptionSettings.Style.ParameterType = $ExceptionStyle.ParameterType
    $exceptionSettings.Style.ParameterName = $ExceptionStyle.ParameterName
    $exceptionSettings.Style.Parenthesis = $ExceptionStyle.Parenthesis
    $exceptionSettings.Style.Path = $ExceptionStyle.Path
    $exceptionSettings.Style.LineNumber = $ExceptionStyle.LineNumber
    $exceptionSettings.Style.Dimmed = $ExceptionStyle.Dimmed
    $exceptionSettings.Style.NonEmphasized = $ExceptionStyle.NonEmphasized

    return [Spectre.Console.ExceptionExtensions]::GetRenderable($exceptionObject, $exceptionSettings)
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectreGrid.ps1


function Format-SpectreGrid {
    <#
    .SYNOPSIS
    Formats data into a Spectre Console grid.

    .DESCRIPTION
    Formats data into a Spectre Console grid. The grid can be used to display data in a tabular format but it's not as flexible as the Layout widget.  
    See https://spectreconsole.net/widgets/grid for more information.

    .PARAMETER Data
    The data to be displayed in the grid. This can be a list of lists or a list of `New-SpectreGridRow` objects.

    .PARAMETER Width
    The width of the grid. If not specified, the grid width will be automatic.

    .PARAMETER Padding
    The padding to apply to the grid items. The default is 1.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to display a grid of rows using the Spectre Console module with a list of lists.
    Format-SpectreGrid -Data @("hello", "I", "am"), @("a", "grid", "of"), @("rows", "using", "spectre")

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to display a grid of rows using the Spectre Console module with a list of `New-SpectreGridRow` objects.
    # The `New-SpectreGridRow` function is used to create the rows when you want to avoid array collapsing in PowerShell turning your rows into a single array of columns.
    $rows = 4
    $cols = 6
    
    $gridRows = @()
    for ($row = 1; $row -le $rows; $row++) {
        $columns = @()
        for ($col = 1; $col -le $cols; $col++) {
            $columns += "Row $row, Col $col" | Format-SpectrePanel
        }
        $gridRows += New-SpectreGridRow $columns
    }
    
    $gridRows | Format-SpectreGrid
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectregrid/')]
    [Reflection.AssemblyMetadata("title", "Format-SpectreGrid")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [GridRowTransformationAttribute()]
        [object]$Data,
        [int] $Width,
        [int] $Padding = 1
    )

    begin {
        $grid = [Spectre.Console.Grid]::new()
        $columnsSet = $false
        if ($Width) {
            $grid.Width = $Width
        }
        $col = [Spectre.Console.GridColumn]::new()
        $grid = $grid.AddColumn()
    }

    process {
        if ($Data -is [array]) {
            foreach ($row in $Data) {
                if (!$columnsSet) {
                    0..($row.Count() - 1) | ForEach-Object {
                        $grid = $grid.AddColumn($col)
                    }
                    $columnsSet = $true
                }
                $grid = $grid.AddRow($row.ToGridRow())
            }
        } else {
            if (!$columnsSet) {
                0..($row.Count() - 1) | ForEach-Object {
                    $grid = $grid.AddColumn($col)
                }
                $columnsSet = $true
            }
            $grid = $grid.AddRow($Data.ToGridRow())
        }
    }
    
    end {
        return $grid
    }
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectreJson.ps1


function Format-SpectreJson {
    <#
    .SYNOPSIS
    Formats an array of objects into a Spectre Console Json.  

    .DESCRIPTION
    This function takes an objects and converts them into syntax highlighted Json using the Spectre Console Json Library.  
    Thanks to [trackd](https://github.com/trackd) for adding this!  
    See https://spectreconsole.net/widgets/json for more information.

    .PARAMETER Data
    The array of objects to be formatted into Json.

    .PARAMETER Depth
    The maximum depth of the Json. Default is defined by the version of powershell.

    .PARAMETER NoBorder
    :::caution
    This parameter is deprecated and will be removed in the future. It takes no effect from version 2.0.
    The json output already has no border.
    :::

    .PARAMETER Border
    :::caution
    This parameter is deprecated and will be removed in the future. It takes no effect from version 2.0.
    To add a border wrap this object in a panel, use `$data | Format-SpectreJson | Format-SpectrePanel`.
    :::

    .PARAMETER Color
    :::caution
    This parameter is deprecated and will be removed in the future. It takes no effect from version 2.0.
    To add a border with a color use `$data | Format-SpectreJson | Format-SpectrePanel -Color "color"`.
    :::

    .PARAMETER Title
    :::caution
    This parameter is deprecated and will be removed in the future. It takes no effect from version 2.0.
    To add a border with a title to the json data, use `$data | Format-SpectreJson | Format-SpectrePanel -Header "title"`.
    :::

    .PARAMETER Width
    :::caution
    This parameter is deprecated and will be removed in the future. It takes no effect from version 2.0.
    To add a border with a width, use `$data | Format-SpectreJson | Format-SpectrePanel -Width 20`.
    :::

    .PARAMETER Height
    :::caution
    This parameter is deprecated and will be removed in the future. It takes no effect from version 2.0.
    To add a border with a width, use `$data | Format-SpectreJson | Format-SpectrePanel -Height 20`.
    :::

    .PARAMETER JsonStyle
    A hashtable of Spectre Console color names and values to style the Json output.
    You can provide a partial hashtable to override only specific styles, the rest will use defaults.
    e.g.
    ```
    @{
        MemberStyle    = "Yellow"
        BracesStyle    = "Red"
        BracketsStyle  = "Orange1"
        ColonStyle     = "White"
        CommaStyle     = "White"
        StringStyle    = "White"
        NumberStyle    = "Red"
        BooleanStyle   = "LightSkyBlue1"
        NullStyle      = "Gray"
    }
    ```

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to format an array of objects into a Spectre Console Json object with syntax highlighting.
    $data = @(
        [pscustomobject]@{
            Name = "John"
            Age = 25
            City = "New York"
            IsEmployed = $true
            Salary = 10
            Hobbies = @("Reading", "Swimming")
            Address = @{
                Street = "123 Main St"
                ZipCode = $null
            }
        }
    )
    Format-SpectreJson -Data $data

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to display json string data using Format-SpectreJson.
    $jsonString = @{
        Name = 'Alice'
        Age = 30
        Skills = @('PowerShell', 'Spectre.Console')
    } | ConvertTo-Json
    
    # Display the JSON string using Format-SpectreJson
    $jsonString | Format-SpectreJson

    .EXAMPLE
    # **Example 3**  
    # This example demonstrates how to display the contents of one or more JSON files directly using Format-SpectreJson.  
    
    # Create temporary JSON files for demonstration, use a random execution ID to avoid reading random json files from the temp directory.
    $executionId = [guid]::NewGuid().ToString()
    $tempJson1 = (New-TemporaryFile).FullName -replace '.tmp$', ".$executionId.json"
    $tempJson2 = (New-TemporaryFile).FullName -replace '.tmp$', ".$executionId.json"
    
    @{
        Name = 'Alice'
        Age = 30
        Skills = @('PowerShell', 'Spectre.Console')
    } | ConvertTo-Json | Set-Content -Path $tempJson1
    
    @{
        Name = 'Bob'
        Age = 35
        Skills = @('C#', 'JavaScript')
    } | ConvertTo-Json | Set-Content -Path $tempJson2
    
    # Display the JSON files directly using Get-ChildItem and Format-SpectreJson
    $parent = Split-Path $tempJson1 -Parent
    Get-ChildItem $parent -Filter "*.$executionId.json" | Format-SpectreJson
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectrejson/')]
    [Reflection.AssemblyMetadata("title", "Format-SpectreJson")]
    [Alias('fsj')]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [object] $Data,
        [int] $Depth,
        [switch] $NoBorder,
        [string] $Border,
        [string] $Color,
        [string] $Title,
        [int] $Width,
        [int] $Height,
        [ColorThemeTransformationAttribute()]
        [hashtable] $JsonStyle = @{}
    )
    begin {

        $defaultJsonStyle = @{
            MemberStyle    = [Spectre.Console.Style]::new($script:AccentColor)
            BracesStyle    = [Spectre.Console.Style]::new([Spectre.Console.Color]::Cyan1)
            BracketsStyle  = [Spectre.Console.Style]::new([Spectre.Console.Color]::Orange1)
            ColonStyle     = [Spectre.Console.Style]::new($script:AccentColor)
            CommaStyle     = [Spectre.Console.Style]::new($script:AccentColor)
            StringStyle    = [Spectre.Console.Style]::new([Spectre.Console.Color]::White)
            NumberStyle    = [Spectre.Console.Style]::new([Spectre.Console.Color]::Cyan1)
            BooleanStyle   = [Spectre.Console.Style]::new([Spectre.Console.Color]::LightSkyBlue1)
            NullStyle      = [Spectre.Console.Style]::new($script:DefaultValueColor)
        }
        Merge-HashtableDefaults -UserStyle $JsonStyle -DefaultStyle $defaultJsonStyle

        $collector = [System.Collections.Generic.List[psobject]]::new()
        $splat = @{
            WarningAction = 'Ignore'
            ErrorAction   = 'Stop'
        }
        if ($Depth) {
            $splat.Depth = $Depth
        }
        $ht = [ordered]@{}
    }
    process {
        if ($MyInvocation.ExpectingInput) {
            if ($data -is [string]) {
                if ($data.pschildname) {
                    if (-Not $ht.contains($data.pschildname)) {
                        $ht[$data.pschildname] = [System.Text.StringBuilder]::new()
                    }
                    return [void]$ht[$data.pschildname].AppendLine($data)
                }
                # assume we get the entire json in one go a string (e.g -Raw or invoke-webrequest)
                try {
                    $jsonObjects = $data | Out-String | ConvertFrom-Json -AsHashtable @splat
                    return $collector.add($jsonObjects)
                } catch {
                    Write-Debug "Failed to convert string to object, $_"
                }
            }
            if ($data -is [System.IO.FileSystemInfo]) {
                if ($data.Extension -eq '.json') {
                    Write-Debug "json file found, reading $($data.FullName)"
                    try {
                        $jsonObjects = Get-Content -Raw $data.FullName | ConvertFrom-Json -AsHashtable @splat
                        return $collector.add($jsonObjects)
                    } catch {
                        Write-Debug "Failed to convert json to object, $_"
                    }
                    
                }
                return $collector.add(
                    [pscustomobject]@{
                        Name     = $data.Name
                        FullName = $data.FullName
                        Type     = $data.GetType().Name.TrimEnd('Info')
                    })
            }
            Write-Debug "adding item from pipeline"
            return $collector.add($data)
        }
        foreach ($item in $data) {
            Write-Debug "adding item from input"
            $collector.add($item)
        }
    }
    end {
        if ($ht.keys.count -gt 0) {
            foreach ($key in $ht.Keys) {
                Write-Debug "converting json stream to object, $key"
                try {
                    $jsonObject = $ht[$key].ToString() | Out-String | ConvertFrom-Json -AsHashtable @splat
                    $collector.add($jsonObject)
                    continue
                } catch {
                    Write-Debug "Failed to convert json to object: $key, $_"
                }
            }
        }
        if ($collector.Count -eq 0) {
            return
        }
        try {
            $json = [Spectre.Console.Json.JsonText]::new(($collector | ConvertTo-Json @splat))
        } catch {
            Write-Error "Failed to convert to json, $_"
            return
        }

        $json.MemberStyle = $JsonStyle.MemberStyle
        $json.BracesStyle = $JsonStyle.BracesStyle
        $json.BracketsStyle = $JsonStyle.BracketsStyle
        $json.ColonStyle = $JsonStyle.ColonStyle
        $json.CommaStyle = $JsonStyle.CommaStyle
        $json.StringStyle = $JsonStyle.StringStyle
        $json.NumberStyle = $JsonStyle.NumberStyle
        $json.BooleanStyle = $JsonStyle.BooleanStyle
        $json.NullStyle = $JsonStyle.NullStyle

        return $json
    }
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectrePadded.ps1


function Format-SpectrePadded {
    <#
    .SYNOPSIS
    Wraps a Spectre Console renderable item in padding.

    .DESCRIPTION
    This function that wraps a spectre renderable item in padding.  
    See https://spectreconsole.net/widgets/padder for more information.

    .PARAMETER Data
    A renderable item to wrap in padding.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to pad an item with a padding of 1 on all sides
    "Item to pad" | Format-SpectrePadded -Padding 1 | Format-SpectrePanel

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to pad an item with a padding of 4 on all sides
    "Item to pad" | Format-SpectrePadded -Padding 4  | Format-SpectrePanel

    .EXAMPLE
    # **Example 3**  
    # This example demonstrates how to pad an item with different padding on each side.
    "Item to pad" | Format-SpectrePadded -Top 4 -Left 10 -Right 1 -Bottom 1 | Format-SpectrePanel
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectrepadded/')]
    [Reflection.AssemblyMetadata("title", "Format-SpectrePadded")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [RenderableTransformationAttribute()]
        [object] $Data,
        [Parameter(ParameterSetName = 'Global', Mandatory)]
        [int] $Padding,
        [Parameter(ParameterSetName = 'Specific', Mandatory)]
        [int] $Top,
        [Parameter(ParameterSetName = 'Specific', Mandatory)]
        [int] $Left,
        [Parameter(ParameterSetName = 'Specific', Mandatory)]
        [int] $Bottom,
        [Parameter(ParameterSetName = 'Specific', Mandatory)]
        [int] $Right,
        [Parameter(ParameterSetName = 'Expand', Mandatory)]
        [switch] $Expand
    )
    
    $paddedRenderable = [Spectre.Console.Padder]::new($Data)

    if ($PSCmdlet.ParameterSetName -eq 'Expand') {
        $paddedRenderable.Expand = $true
    } elseif ($PSCmdlet.ParameterSetName -eq 'Global') {
        $paddedRenderable.Padding = [Spectre.Console.Padding]::new($Padding)
    } elseif ($PSCmdlet.ParameterSetName -eq 'Specific') {
        $paddedRenderable.Padding = [Spectre.Console.Padding]::new($Left, $Top, $Right, $Bottom)
    }

    return $paddedRenderable
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectrePanel.ps1


function Format-SpectrePanel {
    <#
    .SYNOPSIS
    Formats a string as a Spectre Console panel with optional title, border, and color.

    .DESCRIPTION
    This function takes a string and formats it as a Spectre Console panel with optional title, border, and color. The resulting panel can be displayed in the console using the Write-Host command.  
    This function takes a string or renderable object and formats it as a Spectre Console panel with optional title, border, and color. The resulting panel can be displayed in the console using the Write-Host command.  
    
    :::note  
    A panel can only contain a single renderable object. To combine multiple items (such as text and images) in one panel, you'll need to wrap them in a container like Format-SpectreRows or Format-SpectreColumns first. Without this wrapping, Format-SpectrePanel will render each item in a separate panel.
    :::  

    See https://spectreconsole.net/widgets/panel for more information.

    .PARAMETER Data
    The renderable item to be formatted as a panel.

    .PARAMETER Header
    The title to be displayed at the top of the panel.

    .PARAMETER Border
    The type of border to be displayed around the panel.

    .PARAMETER Expand
    Switch parameter that specifies whether the panel should be expanded to fill the available space.

    .PARAMETER Color
    The color of the panel border.

    .PARAMETER Width
    The width of the panel.

    .PARAMETER Height
    The height of the panel.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to display a panel with a title and a rounded border.
    Format-SpectrePanel -Data "Hello, world!" -Title "My Panel" -Border "Rounded" -Color "Red"

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to display a panel with a title and a double border that's expanded to take up the whole console width.
    "Hello, big panel!" | Format-SpectrePanel -Title "My Big Panel" -Border "Double" -Color "Magenta1" -Expand
      .EXAMPLE
    # **Example 3**  
    # This example demonstrates how to combine text and images in a single panel.
    # When combining multiple items in a panel, use Format-SpectreRows or Format-SpectreColumns to wrap them into a single renderable object.
    $message = "Thanks Jeff!"
    $image = Get-SpectreImage -ImagePath ".\private\images\smiley.png" -MaxWidth 25
    @($message, $image) | Format-SpectreRows | Format-SpectrePanel
    
    .EXAMPLE
    # **Example 4**  
    # This example demonstrates how to combine text and images in a single panel with side-by-side layout.
    $message = "Thanks Jeff!"
    $image = Get-SpectreImage -ImagePath ".\private\images\smiley.png" -MaxWidth 25  
    @($message, $image) | Format-SpectreColumns | Format-SpectrePanel
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectrepanel/')]
    [Reflection.AssemblyMetadata("title", "Format-SpectrePanel")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [RenderableTransformationAttribute()]
        [object] $Data,
        [Alias("Title")]
        [string] $Header,
        [ValidateSet([SpectreConsoleBoxBorder], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string] $Border = "Rounded",
        [switch] $Expand,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $Color = $script:AccentColor,
        [ValidateScript({ $_ -gt 0 -and $_ -le (Get-HostWidth) }, ErrorMessage = "Value '{0}' is invalid. Cannot be negative or exceed console width.")]
        [int]$Width,
        [ValidateScript({ $_ -gt 0 }, ErrorMessage = "Value '{0}' is invalid. Cannot be negative.")]
        [int]$Height
    )
    
    process {
        $dataCollection = @($Data)
        foreach ($dataItem in $dataCollection) {
            $panel = [Spectre.Console.Panel]::new($dataItem)
            if ($Header) {
                $panel.Header = [Spectre.Console.PanelHeader]::new($Header)
            }
            if ($width) {
                $panel.Width = $Width
            }
            if ($height) {
                $panel.Height = $Height
            }
            $panel.Expand = $Expand
            $panel.Border = [Spectre.Console.BoxBorder]::$Border
            $panel.BorderStyle = [Spectre.Console.Style]::new($Color)
            return $panel
        }
    }
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectreRows.ps1


function Format-SpectreRows {
    <#
    .SYNOPSIS
    Renders a collection of renderables in rows to the console.

    .DESCRIPTION
    This function creates a spectre rows widget that renders a collection of renderables in autosized rows to the console.  
    Rows can contain renderable items.  
    See https://spectreconsole.net/widgets/rows for more information.

    .PARAMETER Data
    An array of renderable items containing the data to be displayed in the rows.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to display a collection of strings in rows.
    @("top", "middle", "bottom") | Format-SpectreRows

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to display a collection of renderable items as rows inside a panel, without wrapping the renderables in rows you cannot display them in a panel because a panel only accepts a single item.
    $rows = @()
    $bigText = "lorem ipsum dolor sit amet consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt in culpa"
    for ($i = 0; $i -lt 12; $i+= 4) {
        $rows += $bigText | Format-SpectrePadded -Left $i -Top 0 -Bottom 0 -Right 0
    }
    $rows | Format-SpectreRows | Format-SpectrePanel
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectrerows/')]
    [Reflection.AssemblyMetadata("title", "Format-SpectreRows")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [object] $Data,
        [switch] $Expand
    )
    begin {
        $rowItems = @()
    }
    process {
        if ($Data -is [array]) {
            foreach ($dataItem in $Data) {
                if ($dataItem -is [Spectre.Console.Rendering.Renderable]) {
                    $rowItems += $dataItem
                } else {
                    $rowItems += $dataItem | ConvertTo-Renderable
                }
            }
        } else {
            if ($Data -is [Spectre.Console.Rendering.Renderable]) {
                $rowItems += $Data
            } else {
                $rowItems += $Data | ConvertTo-Renderable
            }
        }
    }
    end {
        $rows = [Spectre.Console.Rows]::new($rowItems)
        $rows.Expand = $Expand

        return $rows
    }
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectreTable.ps1


function Format-SpectreTable {
    <#
    .SYNOPSIS
    Formats an array of objects into a Spectre Console table.

    .DESCRIPTION
    This function takes an array of objects and formats them into a table using the Spectre Console library. The table can be customized with a border style and color.  
    Thanks to [trackd](https://github.com/trackd) and [fmotion1](https://github.com/fmotion1) for the updates to support markdown and color in the table contents.  
    See https://spectreconsole.net/widgets/table for more information.

    .PARAMETER Property
    Specifies the object properties that appear in the display and the order in which they appear.
    Type one or more property names, separated by commas, or use a hash table to display a calculated property.
    Wildcards are permitted.
    The Property parameter is optional. You can't use the Property and View parameters in the same command.
    The value of the Property parameter can be a new calculated property.
    The calculated property can be a script block or a hash table. Valid key-value pairs are:
    - Name (or Label) `<string>`
    - Expression - `<string>` or `<script block>`
    - FormatString - `<string>`
    - Width - `<int32>` - must be greater than `0`
    - Alignment - value can be `Left`, `Center`, or `Right`

    .PARAMETER Data
    The array of objects to be formatted into a table.
    Takes pipeline input.

    .PARAMETER Border
    The border style of the table. Default is "Rounded".

    .PARAMETER Color
    The color of the table border. Default is the accent color of the script.

    .PARAMETER HeaderColor
    The color of the table header text. Default is the DefaultTableHeaderColor.

    .PARAMETER TextColor
    The color of the table text. Default is the DefaultTableTextColor.

    .PARAMETER Width
    The width of the table.

    .PARAMETER HideHeaders
    Hides the headers of the table.

    .PARAMETER Title
    The title of the table.

    .PARAMETER ShowRowSeparators
    Shows row separators.

    .PARAMETER AllowMarkup
    Allow Spectre markup in the table elements e.g. [green]message[/].

    .PARAMETER Wrap
    Displays text that exceeds the column width on the next line. By default, text that exceeds the column width is truncated
    Currently there is a bug with this, spectre.console/issues/1185

    .PARAMETER View
    The View parameter lets you specify an alternate format or custom view for the table.

    .PARAMETER Expand
    Take up all of the horizontal space available.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to format an array of objects into a Spectre Console table.
    $data = @(
        [pscustomobject]@{Name="John"; Age=25; City="New York"},
        [pscustomobject]@{Name="Jane"; Age=30; City="Los Angeles"}
    )
    Format-SpectreTable -Data $data

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to format an array of objects into a Spectre Console table with custom properties generated by scriptblock expressions.
    $Properties = @(
        # foreground + background
        @{'Name'='FileName'; Expression={ "[white on DeepSkyBlue3_1]" + $_.Name + "[/]" }},
        # foreground
        @{'Name'='Last Updated'; Expression={ "[DeepSkyBlue3_1]" + $_.LastWriteTime.ToString() + "[/]" }},
        # background
        @{'Name'='Drive'; Expression={ "[black on LightGreen_1]" + $_.PSDrive.Root + "[/]" }}
    )
    Get-ChildItem | Format-SpectreTable -Property $Properties -AllowMarkup

    .EXAMPLE
    # **Example 3**  
    # This example demonstrates how to format an array of scalar objects into a Spectre Console table.
    1..10 | Format-SpectreTable -Title Numbers

    .EXAMPLE
    # **Example 4**  
    # This example demonstrates how to nest other renderable objects inside a table.
    $calendar = Write-SpectreCalendar -Date (Get-Date) -PassThru

    $fruits = @(
        (New-SpectreChartItem -Label "Bananas" -Value 2.2 -Color Yellow),
        (New-SpectreChartItem -Label "Oranges" -Value 6.6 -Color Orange1),
        (New-SpectreChartItem -Label "Apples" -Value 1 -Color Red)
    ) | Format-SpectreBarChart -Width 45

    @{
        Calendar = $calendar
        Fruits = $fruits
    } | Format-SpectreTable -Color Cyan1
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectretable/', DefaultParameterSetName = '__AllParameterSets')]
    [Reflection.AssemblyMetadata("title", "Format-SpectreTable")]
    [Alias('fst')]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [Alias('InputObject')]
        [object] $Data,
        [Parameter(Position = 0, ParameterSetName = 'Property')]
        [object[]] $Property,
        [Switch] $Wrap,
        [Parameter(ParameterSetName = 'View')]
        [String] $View,
        [ValidateSet([SpectreConsoleTableBorder], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string] $Border = "Rounded",
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $Color = $script:AccentColor,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $HeaderColor = $script:DefaultTableHeaderColor,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $TextColor = $script:DefaultTableTextColor,
        [ValidateScript({ $_ -gt 0 -and $_ -le (Get-HostWidth) }, ErrorMessage = "Value '{0}' is invalid. Cannot be negative or exceed console width.")]
        [int] $Width,
        [switch] $HideHeaders,
        [String] $Title,
        [switch] $ShowRowSeparators,
        [switch] $AllowMarkup,
        [switch] $Expand
    )
    begin {
        Write-Debug "Module: $($ExecutionContext.SessionState.Module.Name) Command: $($MyInvocation.MyCommand.Name) Param: $($PSBoundParameters.GetEnumerator())"
        $tableoptions = @{}
        $rowoptions = @{}
        $FormatTableParams = @{}
        $collector = [System.Collections.Generic.List[psobject]]::new()
        $renderables = @{}
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::$Border
        $table.BorderStyle = [Spectre.Console.Style]::new($Color)
        switch ($PSBoundParameters.Keys) {
            'Width' { $table.Width = $Width }
            'HideHeaders' { $table.ShowHeaders = $false }
            'Title' { $tableoptions.Title = $Title }
            'ShowRowSeparators' { [Spectre.Console.TableExtensions]::ShowRowSeparators($table) | Out-Null }
            'AllowMarkup' { $rowoptions.AllowMarkup = $true }
            'Wrap' { $tableoptions.Wrap = $true ; $FormatTableParams.Wrap = $true }
            'View' { $FormatTableParams.View = $View }
            'Property' { $FormatTableParams.Property = $Property }
            'Expand' { $table.Expand = $Expand }
        }
    }
    process {
        foreach ($entry in $data) {
            if ($entry -is [Spectre.Console.Rendering.Renderable]) {
                # The fancy stuff below to handle powershell formatting turns renderable spectre objects into strings.
                # Here we're storing the original object in a lookup table to be read back when it's time to add cells to the table.
                $renderableKey = "RENDERABLE__$([Guid]::NewGuid().Guid)"
                $renderables[$renderableKey] = $entry
                $collector.add($renderableKey)
            } elseif ($entry -is [hashtable] -or $entry -is [ordered]) {
                # Recursively expand values in the hashtable finding any renderables and putting them in the lookup table
                # Renderables is mutable (hashtables just are) so the Convert-HashtableToRenderSafePSObject will add the renderables to the lookup table
                $entry = Convert-HashtableToRenderSafePSObject -Hashtable $entry -Renderables $renderables
                $collector.add($entry)
            } else {
                $collector.add($entry)
            }
        }
    }
    end {
        if ($collector.count -eq 0) {
            return
        }
        if ($FormatTableParams.Keys.Count -gt 0) {
            Write-Debug "Using Format-Table with parameters: $($FormatTableParams.Keys -join ', ')"
            $collector = $collector | Format-Table @FormatTableParams
        } else {
            $collector = $collector | Format-Table
        }
        if (-Not $collector.shapeInfo) {
            # scalar array, no header
            $rowoptions.scalar = $tableoptions.scalar = $true
            $table = Add-TableColumns -Table $table @tableoptions -Color $HeaderColor
        } else {
            # grab the FormatStartData
            $Headers = Get-TableHeader $collector[0]
            if ($Headers) {
                $table = Add-TableColumns -Table $table -formatData $Headers -Color $HeaderColor
            } else {
                return
            }
        }
        foreach ($item in $collector.FormatEntryInfo) {
            if ($rowoptions.scalar) {
                $row = New-TableRow -Entry $item.Text -Renderables $renderables -Color $TextColor @rowoptions
            } else {
                if ($null -eq $item.FormatPropertyFieldList.propertyValue) {
                    continue
                }
                $row = New-TableRow -Entry $item.FormatPropertyFieldList.propertyValue -Renderables $renderables -Color $TextColor @rowoptions
            }
            $table = [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.Renderable[]]$row)
        }
        if ($Title -And -Not $rowoptions.scalar) {
            $table.Title = [Spectre.Console.TableTitle]::new($Title, [Spectre.Console.Style]::new($Color))
        }

        return $table
    }
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectreTextPath.ps1


function Format-SpectreTextPath {
    <#
    .SYNOPSIS
    Formats a path into a Spectre Console Path which supports highlighting and truncating.

    .DESCRIPTION
    Formats a path into a Spectre Console Path which supports highlighting and truncating.  
    See https://spectreconsole.net/widgets/text-path for more information.

    .PARAMETER Path
    The directory/file path to format

    .PARAMETER Alignment
    The alignment of the path. Defaults to "Left".

    .PARAMETER PathStyle
    A hashtable of Spectre Console colors or color names to style the path output.
    You can provide a partial hashtable to override only specific styles, the rest will use defaults.
    e.g.
    ```
    @{
        RootColor      = [Spectre.Console.Color]::Cyan2
        SeparatorColor = [Spectre.Console.Color]::Aqua
        StemColor      = [Spectre.Console.Color]::Orange1
        LeafColor      = "HotPink"
    }
    ```

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to format a PowerShell path as a Spectre Console Path with syntax highlighting.
    Get-Location | Format-SpectreTextPath | Out-SpectreHost
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectretextpath/')]
    [Reflection.AssemblyMetadata("title", "Format-SpectreTextPath")]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string] $Path,
        [ValidateSet([SpectreConsoleJustify], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string] $Alignment = "Left",
        [ColorThemeTransformationAttribute()]
        [hashtable] $PathStyle = @{}
    )

    $defaultPathStyle = @{
        RootColor      = [Spectre.Console.Style]::new($script:AccentColor)
        SeparatorColor = [Spectre.Console.Style]::new($script:DefaultValueColor)
        StemColor      = [Spectre.Console.Style]::new([Spectre.Console.Color]::Orange1)
        LeafColor      = [Spectre.Console.Style]::new([Spectre.Console.Color]::Red)
    }
    Merge-HashtableDefaults -UserStyle $PathStyle -DefaultStyle $defaultPathStyle

    $textPath = [PwshSpectreConsole.Render.SpectreTextPath]::new($Path)
    $textPath.Justification = [Spectre.Console.Justify]::$Alignment
    $textPath.RootStyle = $PathStyle.RootColor
    $textPath.SeparatorStyle = $PathStyle.SeparatorColor
    $textPath.StemStyle = $PathStyle.StemColor
    $textPath.LeafStyle = $PathStyle.LeafColor

    return $textPath
}


#endregion


#region PwshSpectreConsole/public/formatting/Format-SpectreTree.ps1


function Format-SpectreTree {
    <#
    .SYNOPSIS
    Formats a hashtable as a tree using Spectre Console.

    .DESCRIPTION
    This function takes a hashtable and formats it as a tree using Spectre Console. The hashtable should have a 'Value' key and a 'Children' key. The 'Value' key should contain the Spectre Console renderable item (text or other objects like calendars etc.) for the node of the tree, and the 'Children' key should contain an array of hashtables representing the child nodes of the node.  
    See https://spectreconsole.net/widgets/tree for more information.

    .PARAMETER Data
    The hashtable to format as a tree.

    .PARAMETER Guide
    The type of line to use for the tree.

    .PARAMETER Color
    The color to use for the tree. This can be a Spectre Console color name or a hex color code. Default is the accent color defined in the script.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to display a tree with multiple children.
    $calendar = Write-SpectreCalendar -Date 2024-07-01 -PassThru
    $data = @{
        Value = "Root"
        Children = @(
            @{
                Value = "Child 1"
                Children = @(
                    @{
                        Value = "Grandchild 1"
                        Children = @()
                    },
                    @{
                        Value = $calendar
                        Children = @()
                    }
                )
            },
            @{
                Value = "Child 2"
                Children = @()
            }
        )
    }

    Format-SpectreTree -Data $data -Guide BoldLine -Color "Green"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/format-spectretree/')]
    [Reflection.AssemblyMetadata("title", "Format-SpectreTree")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [TreeItemTransformationAttribute()]
        [hashtable] $Data,
        [ValidateSet([SpectreConsoleTreeGuide], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [Alias("Border")]
        [string] $Guide = "Line",
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $Color = $script:AccentColor
    )

    $tree = [Spectre.Console.Tree]::new($Data.Value)
    $tree.Guide = [Spectre.Console.TreeGuide]::$Guide
    $tree.Expanded = $true

    if ($Data.Children) {
        Add-SpectreTreeNode -Node $tree -Children $Data.Children
    }

    $tree.Style = [Spectre.Console.Style]::new($Color)
    
    return $tree
}


#endregion


#region PwshSpectreConsole/public/formatting/New-SpectreChartItem.ps1


function New-SpectreChartItem {
    <#
    .SYNOPSIS
    Creates a new SpectreChartItem object.

    .DESCRIPTION
    The New-SpectreChartItem function creates a new SpectreChartItem object with the specified label, value, and color for use in Format-SpectreBarChart and Format-SpectreBreakdownChart.  

    .PARAMETER Label
    The label for the chart item.

    .PARAMETER Value
    The value for the chart item.

    .PARAMETER Color
    The color for the chart item. Must be a valid Spectre color as name, hex or a Spectre.Console.Color object.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to use SpectreChartItems to create a breakdown chart.
    $data = @()
    $data += New-SpectreChartItem -Label "Sales" -Value 1000 -Color "green"
    $data += New-SpectreChartItem -Label "Expenses" -Value 500 -Color "#ff0000"
    $data += New-SpectreChartItem -Label "Profit" -Value 420 -Color ([Spectre.Console.Color]::Blue)
    Write-SpectreHost "`nGenerate a bar chart`n"
    $data | Format-SpectreBarChart
    Write-SpectreHost "`nGenerate a breakdown chart`n"
    $data | Format-SpectreBreakdownChart
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/new-spectrechartitem/')]
    [Reflection.AssemblyMetadata("title", "New-SpectreChartItem")]
    param (
        [Parameter(Mandatory)]
        [string]$Label,
        [Parameter(Mandatory)]
        [double]$Value,
        [Parameter(Mandatory)]
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color]$Color
    )

    return [SpectreChartItem]::new($Label, $Value, $Color)
}


#endregion


#region PwshSpectreConsole/public/formatting/New-SpectreGridRow.ps1


function New-SpectreGridRow {
    <#
    .SYNOPSIS
    Creates a new SpectreGridRow object.

    .DESCRIPTION
    Creates a new SpectreGridRow object with the specified columns for use in Format-SpectreGrid. PowerShell collapses nested arrays, so you must use this function to create an array of SpectreGridRow objects to provide to Format-SpectreGrid.

    .PARAMETER Data
    An array of renderable items containing the data to be displayed in the columns of this row.

    .PARAMETER Justify
    The justification to apply to each data item in this row. The default is Left.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to create a grid with two rows and three columns.
    $columns = @()
    $columns += "Column 1" | Format-SpectrePanel
    $columns += "Column 2" | Format-SpectrePanel
    $columns += "Column 3" | Format-SpectrePanel

    $rows = @(
    (New-SpectreGridRow -Data $columns),
    (New-SpectreGridRow -Data $columns)
    )

    $rows | Format-SpectreGrid
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/new-spectregridrow/')]
    [Reflection.AssemblyMetadata("title", "New-SpectreGridRow")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [array]$Data
    )

    $renderableColumns = @()
    foreach ($column in $Data) {
        $renderableColumns += ConvertTo-Renderable $column
    }

    $gridRow = [SpectreGridRow]::new($renderableColumns)
    
    return $gridRow
}


#endregion


#region PwshSpectreConsole/public/formatting/New-SpectreLayout.ps1


function New-SpectreLayout {
    <#
    .SYNOPSIS
    Creates a new Spectre Layout object.

    .DESCRIPTION
    The New-SpectreLayout function creates a new Spectre Layout object with the specified data, columns, or rows. This function is used to create a layout object that can be used to split the console into multiple sections.  
    You can only have either rows OR columns in a layout and can compose layouts of layouts to create complex layouts.  

    :::note  
    If you need to know the size of the layout panels you can use the [`Get-SpectreLayoutSizes`](https://pwshspectreconsole.com/reference/measurement/get-spectrelayoutsizes/) function.  
    :::  

    See https://spectreconsole.net/widgets/layout for more information.

    .PARAMETER Data
    The data to be displayed in the layout.

    .PARAMETER Columns
    The columns to be displayed in the layout.

    .PARAMETER Rows
    The rows to be displayed in the layout.

    .PARAMETER Ratio
    The ratio of the layout, when composing layouts of layouts you can use a higher ratio in one layout to make it larger than the other layouts.

    .PARAMETER Name
    The name of the layout, this is used when you want to access one of the layouts in a nested layout to update the contents.  
    e.g. in the example below to update the contents of row1 you would use `$root = $root["row1"].Update(("hello row 1 again" | Format-SpectrePanel))`

    .PARAMETER MinimumSize
    The minimum size of the layout, this can be used to ensure a layout is at least the minimum width.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to create a layout with a calendar, a list of files, and a panel with a calendar aligned to the middle and center.
    $calendar = Write-SpectreCalendar -Date (Get-Date) -PassThru
    $files = Get-ChildItem | Select-Object Name, LastWriteTime -First 3 | Format-SpectreTable | Format-SpectreAligned -HorizontalAlignment Right -VerticalAlignment Bottom

    $panel1 = $files | Format-SpectrePanel -Header "panel 1 (align bottom right)" -Expand -Color Green
    $panel2 = "hello row 2" | Format-SpectrePanel -Header "panel 2" -Expand -Color Blue
    $panel3 = $calendar | Format-SpectreAligned | Format-SpectrePanel -Header "panel 3 (align middle center)" -Expand -Color Yellow

    $row1 = New-SpectreLayout -Name "row1" -Data $panel1 -Ratio 1
    $row2 = New-SpectreLayout -Name "row2" -Columns @($panel2, $panel3) -Ratio 2
    $root = New-SpectreLayout -Name "root" -Rows @($row1, $row2)

    $root | Out-SpectreHost
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/formatting/new-spectrelayout/')]
    [Reflection.AssemblyMetadata("title", "New-SpectreLayout")]
    param (
        [Parameter(ParameterSetName = 'Data')]
        [RenderableTransformationAttribute()]
        [object] $Data,
        # Create a layout with the children layouts as columns
        [Parameter(ParameterSetName = 'Columns', Mandatory)]
        [array] $Columns,
        # Create a layout with the children layouts as rows
        [Parameter(ParameterSetName = 'Rows', Mandatory)]
        [array] $Rows,
        # global params
        [int] $Ratio = 1,
        [string] $Name,
        [int] $MinimumSize = 1
    )

    $layout = [Spectre.Console.Layout]::new($Name)
    $layout.Ratio = $Ratio
    $layout.MinimumSize = $MinimumSize

    if ($PSCmdlet.ParameterSetName -eq 'Columns') {
        $layoutColumns = $Columns | ForEach-Object {
            if ($_ -is [Spectre.Console.Layout]) {
                $_
            } else {
                New-SpectreLayout -Data $_
            }
        }
        $layout = $layout.SplitColumns($layoutColumns)
    } elseif ($PSCmdlet.ParameterSetName -eq 'Rows') {
        $layoutRows = $Rows | ForEach-Object {
            if ($_ -is [Spectre.Console.Layout]) {
                $_
            } else {
                New-SpectreLayout -Data $_
            }
        }
        $layout = $layout.SplitRows($layoutRows)
    } elseif ($PSCmdlet.ParameterSetName -eq 'Data') {
        $layout = $layout.Update($Data)
    }

    return $layout
}


#endregion


#region PwshSpectreConsole/public/images/Get-SpectreImage.ps1


$script:CachedImages = @{}

function Get-SpectreImage {
    <#
    .SYNOPSIS
    Displays an image in the console using CanvasImage or SixelImage if the terminal supports Sixel.

    .DESCRIPTION
    Displays an image in the console using CanvasImage or SixelImage if the terminal supports Sixel.
    The image can be resized to a maximum width if desired.

    Windows Terminal supports Sixel in the [latest preview builds](https://apps.microsoft.com/detail/9n8g5rfz9xk3) so it will be available in the production builds soon 🤞
    See https://www.arewesixelyet.com/ for Sixel support status for your terminal.

    .PARAMETER ImagePath
    The path to the image file to be displayed, as a local path or remote path using http/https.

    .PARAMETER MaxWidth
    The maximum width of the image. If not specified, the image will be displayed at its original size.

    .PARAMETER Format
    The preferred format to use when rendering the image.
    If not specified, the image will be rendered using Sixel if the terminal supports it, otherwise it will use Canvas.

    .PARAMETER Force
    Forces the image to be displayed using the specified format, even if we can't detect Sixel support in the terminal.

    .EXAMPLE
    # **Example 1**
    # When Sixel is not supported the image will use the standard Canvas renderer which draws the image using character cells to represent the image.
    Get-SpectreImage -ImagePath ".\private\images\smiley.png" -MaxWidth 40

    .EXAMPLE
    # **Example 2**
    # For Sixel images, the image returned by `Get-SpectreImage` will render a new frame every time it's drawn so if it's an animated GIF it will appear animated if you render it repeatedly and move the cursor back to the same start position before each image output.
    #
    # ![Spectre Sixel Example](/lapras-terminal.gif)
    #
    NORECORDING
    $image = Get-SpectreImage ".\private\images\lapras-pokemon.gif" -MaxWidth 50

    Clear-Host
    [Console]::CursorVisible = $false

    for($frame = 0; $frame -lt 100; $frame++) {
        [Console]::SetCursorPosition(0, 0)
        $image | Format-SpectrePanel -Title "Frame: $frame" -Color White | Out-SpectreHost
        Start-Sleep -Milliseconds 150
    }
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/images/get-spectreimage/')]
    [Reflection.AssemblyMetadata('title', 'Get-SpectreImage')]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ValueFromPipeline)]
        [Alias('Uri', 'FullName')]
        [string] $ImagePath,
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Width')]
        [int] $MaxWidth,
        [ImageTypes] $Format = 'Auto',
        [switch] $Force,
        [switch] $Animation
    )
    process {
        if ($ImagePath.StartsWith('http://') -or $ImagePath.StartsWith('https://')) {
            if (!$script:CachedImages.ContainsKey($ImagePath) -or -not (Test-Path $script:CachedImages[$ImagePath])) {
                $tempFile = New-TemporaryFile
                Invoke-WebRequest -Uri $ImagePath -UseBasicParsing -OutFile $tempFile -ProgressAction SilentlyContinue
                $script:CachedImages[$ImagePath] = $tempFile.FullName
            }
            $ImagePath = $script:CachedImages[$ImagePath]
        }

        $imagePathResolved = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($ImagePath)
        if (-not (Test-Path -Path $imagePathResolved -PathType Leaf)) {
            # more explicit test for file, otherwise it passes for directories.
            throw "The specified image path '$imagePathResolved' does not exist."
        }

        $image = $null
        if ($Format -eq 'Auto') {
            if ($script:TerminalSupportsSixel -or $Force.IsPresent) {
                $image = [PwshSpectreConsole.PixelImage]::new($imagePathResolved, !$Animation)
            }
            else {
                $image = [PwshSpectreConsole.CellImage]::new($imagePathResolved)
            }
        }
        elseif ($Format -eq 'Sixel') {
            if ($script:TerminalSupportsSixel -or $Force.IsPresent) {
                $image = [PwshSpectreConsole.PixelImage]::new($imagePathResolved, !$Animation)
            }
            else {
                throw 'Sixel format is not supported in this terminal, use -Force to override.'
            }
        }
        else{
            $image = [PwshSpectreConsole.CellImage]::new($imagePathResolved, $Format)
        }
        if ($image -and $MaxWidth) {
            $image.MaxWidth = $MaxWidth
        }
        $image
    }
}


#endregion


#region PwshSpectreConsole/public/images/Get-SpectreImageExperimental.ps1


function Get-SpectreImageExperimental {
    <#
    .SYNOPSIS
    Displays an image in the console using block characters and ANSI escape codes.

    .DESCRIPTION
    This function loads an image from a file and displays it in the console using block characters and ANSI escape codes. The image is scaled to fit within the specified maximum width while maintaining its aspect ratio. If the image is an animated GIF, each frame is displayed in sequence.  
    The images rendered by this experimental function are not handled by Spectre Console, it's using a PowerShell script to render the image in a higher resolution than Spectre.Console does by using half-block characters.
    :::danger
    This has been deprecated and will be removed in PwshSpectreConsole v3.0.  
    :::

    .PARAMETER ImagePath
    The path to the image file to display.

    .PARAMETER ImageUrl
    The URL to the image file to display. If specified, the image is downloaded to a temporary file and then displayed.

    .PARAMETER Width
    The width of the image in characters. The image is scaled to fit within this width while maintaining its aspect ratio.

    .PARAMETER LoopCount
    The number of times to repeat the animation. The default value is 0, which means the animation will repeat forever. Press ctrl-c to stop the animation.

    .PARAMETER Resampler
    The resampling algorithm to use when scaling the image. Valid values are "Bicubic" and "NearestNeighbor". The default value is "Bicubic".

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to display an animated image in the console that loops 4 times.
    Get-SpectreImageExperimental -ImagePath ".\private\images\harveyspecter.gif" -LoopCount 4 -Width 82

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to display a static image in the console.
    Get-SpectreImageExperimental -ImagePath ".\private\images\smiley.png" -Width 80
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/images/get-spectreimageexperimental/')]
    [Reflection.AssemblyMetadata("title", "Get-SpectreImageExperimental")]
    param (
        [string] $ImagePath,
        [uri] $ImageUrl,
        [int] $Width,
        [int] $LoopCount = 0,
        [ValidateSet("Bicubic", "NearestNeighbor")]
        [string] $Resampler = "Bicubic"
    )

    Write-Warning "Get-SpectreImageExperimental has been deprecated and will be removed in PwshSpectreConsole v3.0. Use Get-SpectreImage instead."

    $spectreConsole = [Spectre.Console.AnsiConsole]::Console
    $spectreConsoleHeight = $spectreConsole.Profile.Height

    try {
        if ($ImageUrl) {
            $ImagePath = New-TemporaryFile
            Invoke-WebRequest -Uri $ImageUrl -OutFile $ImagePath
        }
        $imagePathResolved = Resolve-Path $ImagePath
        if (-not (Test-Path $imagePathResolved)) {
            throw "The specified image path '$resolvedImagePath' does not exist."
        }

        $backgroundColor = [System.Drawing.Color]::FromName([Console]::BackgroundColor)

        $image = [SixLabors.ImageSharp.Image]::Load($imagePathResolved)

        if ($Width) {
            $maxWidth = $Width
        } else {
            $maxWidth = $spectreConsole.Profile.Out.Width
            $Width = $image.Width
        }
        $maxHeight = ($spectreConsoleHeight) * 2
        $scaledHeight = [int]($image.Height * ($Width / $image.Width))
        if ($scaledHeight -gt $maxHeight) {
            $scaledHeight = $maxHeight
        }

        $scaledWidth = [int]($image.Width * ($scaledHeight / $image.Height))
        if ($scaledWidth -gt $maxWidth) {
            $scaledWidth = $maxWidth
            $scaledHeight = [int]($image.Height * ($scaledWidth / $image.Width))
        }

        [SixLabors.ImageSharp.Processing.ProcessingExtensions]::Mutate($image, {
                param($Context)
                [SixLabors.ImageSharp.Processing.ResizeExtensions]::Resize(
                    $Context,
                    $scaledWidth,
                    $scaledHeight,
                    [SixLabors.ImageSharp.Processing.KnownResamplers]::$Resampler
                )
            })

        $frames = [System.Collections.Generic.List[hashtable]]::new()
        $buffer = [System.Text.StringBuilder]::new($scaledWidth * $scaledHeight * 2)

        foreach ($frame in $image.Frames) {
            $frameDelayMilliseconds = 1000
            try {
                $frameMetadata = [SixLabors.ImageSharp.MetadataExtensions]::GetGifMetadata($frame.Metadata)
                if ($frameMetadata.FrameDelay) {
                    # The delay is supposed to be in milliseconds and imagesharp seems to be a bit out when it decodes it
                    $frameDelayMilliseconds = $frameMetadata.FrameDelay * 10
                }
            } catch {
                # Don't care
            }
            $buffer.Clear() | Out-Null
            for ($y = 0; $y -lt $scaledHeight; $y += 2) {
                if (($y + 1) -ge $scaledHeight) {
                    # The image is not an even number of pixels high and we're rendering two at a time, trim the last row if it's partial
                    $buffer.AppendLine() | Out-Null
                    break
                }
                for ($x = 0; $x -lt $scaledWidth; $x++) {
                    $currentPixel = $frame[$x, $y]
                    if ($null -ne $currentPixel.A) {
                        # Quick-hack blending the foreground with the terminal background color. This could be done in imagesharp
                        $foregroundMultiplier = $currentPixel.A / 255
                        $backgroundMultiplier = 100 - $foregroundMultiplier
                        $currentPixelRgb = @{
                            R = [math]::Min(255, ($currentPixel.R * $foregroundMultiplier + $backgroundColor.R * $backgroundMultiplier))
                            G = [math]::Min(255, ($currentPixel.G * $foregroundMultiplier + $backgroundColor.G * $backgroundMultiplier))
                            B = [math]::Min(255, ($currentPixel.B * $foregroundMultiplier + $backgroundColor.B * $backgroundMultiplier))
                        }
                    } else {
                        $currentPixelRgb = @{
                            R = $currentPixel.R
                            G = $currentPixel.G
                            B = $currentPixel.B
                        }
                    }

                    # Parse the image 2 vertical pixels at a time and use the lower half block character with varying foreground and background colors to
                    # make it appear as two pixels within one character space
                    if ($image.Height -ge ($y + 1)) {
                        $pixelBelow = $frame[$x, ($y + 1)]

                        if ($null -ne $pixelBelow.A) {
                            # Quick-hack blending the foreground with the terminal background color. This could be done in imagesharp
                            $foregroundMultiplier = $pixelBelow.A / 255
                            $backgroundMultiplier = 100 - $foregroundMultiplier
                            $pixelBelowRgb = @{
                                R = [math]::Min(255, ($pixelBelow.R * $foregroundMultiplier + $backgroundColor.R * $backgroundMultiplier))
                                G = [math]::Min(255, ($pixelBelow.G * $foregroundMultiplier + $backgroundColor.G * $backgroundMultiplier))
                                B = [math]::Min(255, ($pixelBelow.B * $foregroundMultiplier + $backgroundColor.B * $backgroundMultiplier))
                            }
                        } else {
                            $pixelBelowRgb = @{
                                R = $pixelBelow.R
                                G = $pixelBelow.G
                                B = $pixelBelow.B
                            }
                        }

                        $transparentCurrentPixel = $false
                        if($null -ne $pixelBelow.A -and $pixelBelow.A -lt 5) {
                            $buffer.Append("$([Char]27)[0m") | Out-Null
                            $transparentCurrentPixel = $true
                        } else {
                            $buffer.Append(("$([Char]27)[38;2;{0};{1};{2}m" -f
                                    $pixelBelowRgb.R,
                                    $pixelBelowRgb.G,
                                    $pixelBelowRgb.B
                                )) | Out-Null
                        }
                    } else {
                        $buffer.Append("$([Char]27)[0mX") | Out-Null
                        $transparentCurrentPixel = $true
                    }

                    if($transparentCurrentPixel -or ($null -ne $currentPixel.A -and $currentPixel.A -lt 5)) {
                        $buffer.Append("$([Char]27)[0m ") | Out-Null
                    } else {
                        $buffer.Append(("$([Char]27)[48;2;{0};{1};{2}m$([Char]0x2584)$([Char]27)[0m" -f
                                $currentPixelRgb.R,
                                $currentPixelRgb.G,
                                $currentPixelRgb.B
                            )) | Out-Null
                    }
                }
                $buffer.AppendLine() | Out-Null
            }

            $frames.Add(@{
                    FrameDelayMilliseconds = $frameDelayMilliseconds
                    Frame                  = $buffer.ToString().Trim()
                }
            )
        }

        $loopIterations = 0
        [Console]::CursorVisible = $false

        # Just one frame, print the image and return
        if ($frames.Count -eq 1) {
            $spectreConsole.Profile.Out.Writer.Write($frames[0].Frame)
            return
        }

        # The cursor needs to be returned to the top left of the image after every frame apart from the last
        $imageLines = $frames[0].Frame.Split("`n").Count - 1
        $returnLinesEscapeCode = "`r`e[${imageLines}A"
        do {
            $animationFrameReturnLines = $returnLinesEscapeCode
            for ($f = 0; $f -lt $frames.Count; $f++) {
                if($f -eq ($frames.Count - 1) -and $loopIterations -eq ($LoopCount - 1)) {
                    $animationFrameReturnLines = ""
                }
                $frame = $frames[$f]
                $spectreConsole.Profile.Out.Writer.Write($frame.Frame + $animationFrameReturnLines)
                Start-Sleep -Milliseconds $frame.FrameDelayMilliseconds
            }
            $loopIterations++
        } while ($loopIterations -lt $LoopCount -or $LoopCount -eq 0)
    } finally {
        [Console]::CursorVisible = $true
        if ($ImageUrl) {
            Remove-Item $ImagePath
        }
        Write-SpectreHost " "
    }
}


#endregion


#region PwshSpectreConsole/public/live/Add-SpectreJob.ps1


function Add-SpectreJob {
    <#
    .SYNOPSIS
    Adds a Spectre job to a list of jobs.

    .DESCRIPTION
    This function adds a Spectre job to the list of jobs you want to wait for with Wait-SpectreJobs.  
    To retrieve the outcome of the job you need to use the standard PowerShell Receive-Job cmdlet.
    :::note
    This is only used inside `Invoke-SpectreCommandWithProgress` where the Spectre ProgressContext object is exposed.
    :::

    .PARAMETER Context
    The Spectre context to add the job to. The context object is only available inside Invoke-SpectreCommandWithProgress.
    [https://spectreconsole.net/api/spectre.console/progresscontext/](https://spectreconsole.net/api/spectre.console/progresscontext/)

    .PARAMETER JobName
    The name of the job to add.

    .PARAMETER Job
    The PowerShell job to add to the context.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to add two jobs to a context and wait for them to complete.
    
    $jobOutcomes = Invoke-SpectreCommandWithProgress -ScriptBlock {
        param (
            [Spectre.Console.ProgressContext] $Context
        )
        $jobs = @()
        $jobs += Add-SpectreJob -Context $Context -JobName "job 1" -Job (Start-Job { Start-Sleep -Seconds 2 })
        $jobs += Add-SpectreJob -Context $Context -JobName "job 2" -Job (Start-Job { Start-Sleep -Seconds 4 })
        Wait-SpectreJobs -Context $Context -Jobs $jobs
        return $jobs.Job
    }
    $jobOutcomes | Format-SpectreTable -Property Id, Name, PSJobTypeName, State, Command
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/live/add-spectrejob/')]
    [Reflection.AssemblyMetadata("title", "Add-SpectreJob")]
    param (
        [Parameter(Mandatory)]
        [Spectre.Console.ProgressContext] $Context,
        [Parameter(Mandatory)]
        [string] $JobName,
        [Parameter(Mandatory)]
        [System.Management.Automation.Job] $Job
    )

    return @{
        Job  = $Job
        Task = $Context.AddTask($JobName)
    }
}


#endregion


#region PwshSpectreConsole/public/live/Invoke-SpectreCommandWithProgress.ps1


function Invoke-SpectreCommandWithProgress {
    <#
    .SYNOPSIS
    Invokes a Spectre command with a progress bar.

    .DESCRIPTION
    This function takes a script block as a parameter and executes it while displaying a progress bar. The context and task objects are defined at [https://spectreconsole.net/api/spectre.console/progresscontext/](https://spectreconsole.net/api/spectre.console/progresscontext/).  
    The context requires at least one task to be added for progress to be displayed. The task object is used to update the progress bar by calling the `Increment()` method or other methods defined in Spectre console [https://spectreconsole.net/api/spectre.console/progresstask/](https://spectreconsole.net/api/spectre.console/progresstask/).  
    See https://spectreconsole.net/live/progress for more information.

    .PARAMETER ScriptBlock
    The script block to execute.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates a 4-stage process with one loading bar that loads in four chunks.
    
    Invoke-SpectreCommandWithProgress -ScriptBlock {
        param (
            [Spectre.Console.ProgressContext] $Context
        )
        # AddTask() returns a https://spectreconsole.net/api/spectre.console/progresstask/ object
        $task1 = $Context.AddTask("A 4-stage process")
        Start-Sleep -Seconds 1
        $task1.Increment(25)
        Start-Sleep -Seconds 1
        $task1.Increment(25)
        Start-Sleep -Seconds 1
        $task1.Increment(25)
        Start-Sleep -Seconds 1
        $task1.Increment(25)
        Start-Sleep -Seconds 1
    }

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates a 2-stage process with two loading bars running in parallel.

    Invoke-SpectreCommandWithProgress -ScriptBlock {
        param (
            [Spectre.Console.ProgressContext] $Context
        )
        
        $jobs = @()
        $jobs += Add-SpectreJob -Context $Context -JobName "Drawing a picture" -Job (
            Start-Job {
                $progress = 0
                while($progress -lt 100) {
                    $progress += 1.5
                    Write-Progress -Activity "Processing" -PercentComplete $progress
                    Start-Sleep -Milliseconds 50
                }
            }
        )
        $jobs += Add-SpectreJob -Context $Context -JobName "Driving a car" -Job (
            Start-Job {
                $progress = 0
                while($progress -lt 100) {
                    $progress += 0.9
                    Write-Progress -Activity "Processing" -PercentComplete $progress
                    Start-Sleep -Milliseconds 50
                }
            }
        )
        
        Wait-SpectreJobs -Context $Context -Jobs $jobs
    }

    .EXAMPLE
    # **Example 3**  
    # This example demonstrates a task with an unknown (indeterminate) duration.
    
    $result = Invoke-SpectreCommandWithProgress -ScriptBlock {
        param (
            [Spectre.Console.ProgressContext] $Context
        )
        
        $task1 = $Context.AddTask("Task with unknown duration")
        $task1.IsIndeterminate = $true
        Start-Sleep -Seconds 5
        $task1.Value = 100

        return "Some result"
    }
    Write-SpectreHost "Result: $result"

    .EXAMPLE
    # **Example 4**  
    # This example demonstrates a job with an estimated duration, after the estimated duration has passed the job will switch to an indeterminate state.

    $result = Invoke-SpectreCommandWithProgress -ScriptBlock {
        param (
            [Spectre.Console.ProgressContext] $Context
        )
        
        $job = Add-SpectreJob -Context $Context -JobName "Doing some work" -Job (
            Start-Job {
                Start-Sleep -Seconds 10
                return 1234
            }
        )
        
        Wait-SpectreJobs -Context $Context -Jobs $job -EstimatedDurationSeconds 5
        
        $result = Receive-Job -Job $job.Job
        
        return $result
    }
    Write-SpectreHost "Result: $result"

    .EXAMPLE
    # **Example 5**  
    # This example demonstrates how to track the progress of ForEach-Object -Parallel jobs with a progress bar.
    $OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    $jobs = 1..10 | ForEach-Object -AsJob -ThrottleLimit 3 -Parallel {
        Start-Sleep -Seconds (Get-Random -Minimum 1 -Maximum 5)
    }
    Invoke-SpectreCommandWithProgress -ScriptBlock {
        param (
            [Spectre.Console.ProgressContext] $Context
        )
        $task = $Context.AddTask("Waiting for jobs to complete")
        do {
            $completedCount = $jobs.ChildJobs.Where{ $_.State -eq "Completed" }.Count
            $totalCount = $jobs.ChildJobs.Count
            $percentComplete = [math]::Round($completedCount / $totalCount * 100, 0)
            if ($percentComplete -gt $task.Percentage) {
                $task.Increment($percentComplete - $task.Percentage)
            }
            if ($jobs.State -eq "Running") {
                Start-Sleep -Milliseconds 500
            }
        } until ($jobs.State -eq "Completed")
        $task.Increment(100 - $task.Percentage)
    }
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/live/invoke-spectrecommandwithprogress/')]
    [Reflection.AssemblyMetadata("title", "Invoke-SpectreCommandWithProgress")]
    param (
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock
    )
    Start-AnsiConsoleProgress $ScriptBlock
}


#endregion


#region PwshSpectreConsole/public/live/Invoke-SpectreCommandWithStatus.ps1


function Invoke-SpectreCommandWithStatus {
    <#
    .SYNOPSIS
    Invokes a script block with a Spectre status spinner.

    .DESCRIPTION
    This function starts a Spectre status spinner with the specified title and spinner type, and invokes the specified script block. The spinner will continue to spin until the script block completes.  
    See https://spectreconsole.net/live/status for more information.

    .PARAMETER ScriptBlock
    The script block to invoke.

    .PARAMETER Spinner
    The type of spinner to display.

    .PARAMETER Title
    The title to display above the spinner.

    .PARAMETER Color
    The color of the spinner. Valid values can be found with Get-SpectreDemoColors.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to show a spinner while doing some work. Write-SpectreHost is used to update the host with progress without breaking the spinner animation.
    
    $result = Invoke-SpectreCommandWithStatus -Spinner "Dots2" -Title "Showing a spinner..." -ScriptBlock {
        # Write updates to the host using Write-SpectreHost
        Start-Sleep -Seconds 1
        Write-SpectreHost "`n[grey]LOG:[/] Doing some work      "
        Start-Sleep -Seconds 1
        Write-SpectreHost "`n[grey]LOG:[/] Doing some more work "
        Start-Sleep -Seconds 1
        Write-SpectreHost "`n[grey]LOG:[/] Done                 "
        Start-Sleep -Seconds 1
        Write-SpectreHost " "
        return "Some result"
    }
    Write-SpectreHost "Result: $result"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/live/invoke-spectrecommandwithstatus/')]
    [Reflection.AssemblyMetadata("title", "Invoke-SpectreCommandWithStatus")]
    param (
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,
        [ValidateSet([SpectreConsoleSpinner], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string] $Spinner = "Dots",
        [Parameter(Mandatory)]
        [string] $Title,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $Color = $script:AccentColor
    )
    $splat = @{
        Title        = $Title
        Spinner      = [Spectre.Console.Spinner+Known]::$Spinner
        SpinnerStyle = [Spectre.Console.Style]::new($Color)
        ScriptBlock  = $ScriptBlock
    }
    Start-AnsiConsoleStatus @splat
}


#endregion


#region PwshSpectreConsole/public/live/Invoke-SpectreLive.ps1


function Invoke-SpectreLive {
    <#
    .SYNOPSIS
    Invokes a script block with live rendering.

    .DESCRIPTION
    Starts live rendering for a given renderable. The script block is able to update the renderable in real-time and Spectre Console redraws every time the scriptblock calls `$Context.refresh()`.  

    :::note  
    If you need to know the size of the layouts you can use the [`Get-SpectreLayoutSizes`](https://pwshspectreconsole.com/reference/measurement/get-spectrelayoutsizes/) function.  
    :::  

    See https://spectreconsole.net/live/live-display for more information.

    .PARAMETER Data
    The renderable object to render.

    .PARAMETER ScriptBlock
    The script block to execute while the live renderable is being rendered.

    .EXAMPLE
    # **Example 1**  
    # This is a live updating table example, the table will be updated every second with a new row.
    $data = @(
        [pscustomobject]@{Name="John"; Age=25; City="New York"},
        [pscustomobject]@{Name="Jane"; Age=30; City="Los Angeles"}
    )
    $table = Format-SpectreTable -Data $data

    Invoke-SpectreLive -Data $table -ScriptBlock {
        param (
            [Spectre.Console.LiveDisplayContext] $Context
        )
        $Context.refresh()
        for ($i = 0; $i -lt 5; $i++) {
            Start-Sleep -Seconds 1
            $table = Add-SpectreTableRow -Table $table -Columns "Shaun $i", $i, "Wellington"
            $Context.refresh()
        }
    }

    .EXAMPLE
    # **Example 2**  
    # This is a complex live updating nested layout example. It demonstrates how to create a file browser with a preview panel.
    # The root layout is constructed with a header and a content panel. The content panel is split into two columns: filelist and preview.
    # Invoke-SpectreLive is used to render the layout and update the content of each panel on every loop iteration until the escape key is pressed.
    $layout = New-SpectreLayout -Name "root" -Rows @(
        # Row 1
        (
            New-SpectreLayout -Name "header" -MinimumSize 5 -Ratio 1 -Data ("empty")
        ),
        # Row 2
        (
            New-SpectreLayout -Name "content" -Ratio 10 -Columns @(
                (
                    New-SpectreLayout -Name "filelist" -Ratio 2 -Data "empty"
                ),
                (
                    New-SpectreLayout -Name "preview" -Ratio 4 -Data "empty"
                )
            )
        )
    )

    # Functions for rendering the content of each panel
    function Get-TitlePanel {
        return "File Browser - Spectre Live Demo [gray]$(Get-Date)[/]" | Format-SpectreAligned -HorizontalAlignment Center -VerticalAlignment Middle | Format-SpectrePanel -Expand
    }

    function Get-FileListPanel {
        param (
            $Files,
            $SelectedFile
        )
        $fileList = $Files | ForEach-Object {
            $name = $_.Name
            if ($_.Name -eq $SelectedFile.Name) {
                $name = "[Turquoise2]$($name)[/]"
            }
            return $name
        } | Out-String
        return Format-SpectrePanel -Header "[white]File List[/]" -Data $fileList.Trim() -Expand
    }

    function Get-PreviewPanel {
        param (
            $SelectedFile
        )
        $item = Get-Item -Path $SelectedFile.FullName
        $result = ""
        if ($item -is [System.IO.DirectoryInfo]) {
            $result = "[grey]$($SelectedFile.Name) is a directory.[/]"
        } elseif ($item.Name -match "\.(jpg|jpeg|png|gif)$") {
            $result = Get-SpectreSixelImage $item.FullName
        } else {
            try {
                $content = Get-Content -Path $item.FullName -Raw -ErrorAction Stop
                $result = "[grey]$($content | Get-SpectreEscapedText)[/]"
            } catch {
                $result = "[red]Error reading file content: $($_.Exception.Message | Get-SpectreEscapedText)[/]"
            }
        }
        return $result | Format-SpectrePanel -Header "[white]Preview[/]" -Expand
    }

    function Get-LastKeyPressed {
        $lastKeyPressed = $null
        while ([Console]::KeyAvailable) {
            $lastKeyPressed = [Console]::ReadKey($true)
        }
        return $lastKeyPressed
    }

    # Start live rendering the layout
    # Type "↓", "↓", "↓" to navigate the file list, and press "Enter" to open a file in Notepad
    Invoke-SpectreLive -Data $layout -ScriptBlock {
        param (
            [Spectre.Console.LiveDisplayContext] $Context
        )

        # State
        $fileList = @(@{Name = ".."; Fullname = ".."}) + (Get-ChildItem)
        $selectedFile = $fileList[0]

        while ($true) {
            # Handle input
            $lastKeyPressed = Get-LastKeyPressed
            if ($lastKeyPressed -ne $null) {
                if ($lastKeyPressed.Key -eq "DownArrow") {
                    $selectedFile = $fileList[($fileList.IndexOf($selectedFile) + 1) % $fileList.Count]
                } elseif ($lastKeyPressed.Key -eq "UpArrow") {
                    $selectedFile = $fileList[($fileList.IndexOf($selectedFile) - 1 + $fileList.Count) % $fileList.Count]
                } elseif ($lastKeyPressed.Key -eq "Enter") {
                    if ($selectedFile -is [System.IO.DirectoryInfo] -or $selectedFile.Name -eq "..") {
                        $fileList = @(@{Name = ".."; Fullname = ".."}) + (Get-ChildItem -Path $selectedFile.FullName)
                        $selectedFile = $fileList[0]
                    } else {
                        notepad $selectedFile.FullName
                        return
                    }
                } elseif ($lastKeyPressed.Key -eq "Escape") {
                    return
                }
            }

            # Generate new data
            $titlePanel = Get-TitlePanel
            $fileListPanel = Get-FileListPanel -Files $fileList -SelectedFile $selectedFile
            $previewPanel = Get-PreviewPanel -SelectedFile $selectedFile

            # Update layout
            $layout["header"].Update($titlePanel) | Out-Null
            $layout["filelist"].Update($fileListPanel) | Out-Null
            $layout["preview"].Update($previewPanel) | Out-Null

            # Draw changes
            $Context.Refresh()
            Start-Sleep -Milliseconds 200
        }
    }

    .EXAMPLE
    # **Example 3**  
    # This is a simple example of creating a chat application. In this example a different approach is used to render the components, each component has been passed a copy of the context and layout object so it can update itself.

    Set-SpectreColors -AccentColor DeepPink1

    # Build root layout scaffolding for:
    # +--------------------------------+
    # |             Title              | <- Update-TitleComponent will render the title
    # |--------------------------------|
    # |                                | <- Update-MessageListComponent will display the list of messages here
    # |                                |
    # |            Messages            |
    # |                                |
    # |                                |
    # |--------------------------------|
    # |        CustomTextEntry         | <- Update-CustomTextEntryComponent will create a text entry prompt here that is manually managed by pushing keys into a string
    # |________________________________|

    $layout = New-SpectreLayout -Name "root" -Rows @(
        # Row 1
        (New-SpectreLayout -Name "title" -MinimumSize 5 -Ratio 1 -Data ("empty")),
        # Row 2
        (New-SpectreLayout -Name "messages" -Ratio 10 -Data ("empty")),
        # Row 3
        (New-SpectreLayout -Name "customTextEntry" -MinimumSize 5 -Ratio 1 -Data ("empty"))
    )

    # Component functions for rendering the content of each panel
    function Update-TitleComponent {
        param (
            [Spectre.Console.LiveDisplayContext] $Context,
            [Spectre.Console.Layout] $LayoutComponent
        )
        $component = @(
            ("🧠 ChaTTY" | Format-SpectreAligned -HorizontalAlignment Center -VerticalAlignment Middle | Format-SpectrePadded -Padding 1),
            (Write-SpectreRule -LineColor DeepPink1 -PassThru)
        ) | Format-SpectreRows | Format-SpectrePanel -Border None
        $LayoutComponent.Update($component) | Out-Null
        $Context.Refresh()
    }

    function Update-MessageListComponent {
        param (
            [Spectre.Console.LiveDisplayContext] $Context,
            [Spectre.Console.Layout] $LayoutComponent,
            [System.Collections.Stack] $Messages
        )

        $rows = @()

        foreach ($message in $Messages) {
            if ($message.Actor -eq "System") {
                $rows += $message.Message.PadRight(6) `
                    | Get-SpectreEscapedText `
                    | Write-SpectreHost -Justify Left -PassThru `
                    | Format-SpectrePanel -Color Grey -Header "System" `
                    | Format-SpectreAligned -HorizontalAlignment Left `
                    | Format-SpectrePadded -Top 0 -Left 10 -Bottom 0 -Right 0
            } else {
                $rows += $message.Message.PadRight($message.Actor.Length) `
                    | Get-SpectreEscapedText `
                    | Write-SpectreHost -Justify Right -PassThru `
                    | Format-SpectrePanel -Color Pink1 -Header $message.Actor `
                    | Format-SpectreAligned -HorizontalAlignment Right `
                    | Format-SpectrePadded -Top 0 -Left 0 -Bottom 0 -Right 10
            }
        }

        # Add the heights of each message until reaching the max size, subtract the height of the title and text entry components (10)
        $availableHeight = $Host.UI.RawUI.WindowSize.Height - 10
        $totalHeight = 0
        $rowsToRender = @()
        foreach ($row in $rows) {
            $totalHeight += ($row | Get-SpectreRenderableSize).Height
            if ($totalHeight -gt $availableHeight) {
                break
            }
            $rowsToRender += $row
        }

        # Stack is LIFO, so we need to reverse it to display the messages in the correct order
        [array]::Reverse($rowsToRender)

        $component = $rowsToRender | Format-SpectreRows | Format-SpectreAligned -VerticalAlignment Top | Format-SpectrePanel -Border None
        $LayoutComponent.Update($component) | Out-Null
        $Context.Refresh()
    }

    function Update-CustomTextEntryComponent {
        param (
            [Spectre.Console.LiveDisplayContext] $Context,
            [Spectre.Console.Layout] $LayoutComponent,
            [string] $CurrentInput
        )
        $safeInput = [string]::IsNullOrEmpty($CurrentInput) ? "" : ($CurrentInput | Get-SpectreEscapedText)
        $component = "[gray]Prompt:[/] $safeInput" | Format-SpectrePanel -Expand | Format-SpectrePadded -Top 0 -Left 20 -Bottom 0 -Right 20 | Format-SpectreAligned -HorizontalAlignment Center
        $LayoutComponent.Update($component) | Out-Null
        $Context.Refresh()
    }

    # App logic functions
    function Get-SomeChatResponse {
        param (
            [System.Collections.Stack] $Messages,
            [Spectre.Console.LiveDisplayContext] $Context,
            [Spectre.Console.Layout] $LayoutComponent
        )

        # Pretend to be thinking
        $ellipsisCount = 1
        for ($i = 0; $i -lt 3; $i++) {
            $Messages.Push(@{ Actor = "System"; Message = ("." * $ellipsisCount) })
            $ellipsisCount++

            Update-MessageListComponent -Context $Context -LayoutComponent $LayoutComponent -Messages $Messages
            Start-Sleep -Milliseconds 500

            # Remove the last thinking message
            $null = $Messages.Pop()
        }

        # Return the response
        return @{ Actor = "System"; Message = "I don't understand what you're saying." }
    }

    function Get-LastChatKeyPressed {
        return [Console]::ReadKey($true)
    }

    # Start live rendering the layout
    Invoke-SpectreLive -Data $layout -ScriptBlock {
        param (
            [Spectre.Console.LiveDisplayContext] $Context
        )

        # State
        $messages = [System.Collections.Stack]::new(@(
            @{ Actor = "System"; Message = "👋 Hello, welcome to ChaTTY!" },
            @{ Actor = "System"; Message = "Type your message and press Enter to send it." },
            @{ Actor = "System"; Message = "Use the Up and Down arrow keys to scroll through previous messages." },
            @{ Actor = "System"; Message = "Press 'ctrl-c' to close the chat." }
        ))
        $currentInput = ""

        while ($true) {
            # Update components
            Update-TitleComponent -Context $Context -LayoutComponent $layout["title"]
            Update-MessageListComponent -Context $Context -LayoutComponent $layout["messages"] -Messages $messages
            Update-CustomTextEntryComponent -Context $Context -LayoutComponent $layout["customTextEntry"] -CurrentInput $currentInput

            # Real basic input handling, just add characters and remove if backspace is pressed, submit message if Enter is pressed
            [Console]::TreatControlCAsInput = $true
            $lastKeyPressed = Get-LastChatKeyPressed
            if ($lastKeyPressed.Key -eq "C" -and $lastKeyPressed.Modifiers -eq "Control") {
                # Exit the loop. You have to treat ctrl-c as input to avoid the console readkey blocking the sigint
                return
            } elseif ($lastKeyPressed.Key -eq "Enter") {
                # Add the latest user message to the message stack
                $messages.Push(@{ Actor = ($env:USERNAME + $env:USER); Message = $currentInput })
                $currentInput = ""
                Update-CustomTextEntryComponent -Context $Context -LayoutComponent $layout["customTextEntry"] -CurrentInput $currentInput
                Update-MessageListComponent -Context $Context -LayoutComponent $layout["messages"] -Messages $messages
                $messages.Push((Get-SomeChatResponse -Messages $messages -Context $Context -LayoutComponent $layout["messages"]))
            } elseif($lastKeyPressed.Key -eq "Backspace") {
                # Remove the last character from the current input string
                $currentInput = $currentInput.Substring(0, [Math]::Max(0, $currentInput.Length - 1))
            } elseif ($lastKeyPressed.KeyChar) {
                # Add the character to the current input string
                $currentInput += $lastKeyPressed.KeyChar
            }
        }
    }
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/live/invoke-spectrelive/')]
    [Reflection.AssemblyMetadata("title", "Invoke-SpectreLive")]
    param (
        [Parameter(ValueFromPipeline)]
        [RenderableTransformationAttribute()]
        [object] $Data,
        [scriptblock] $ScriptBlock
    )

    Start-AnsiConsoleLive -Data $Data -ScriptBlock $ScriptBlock
}


#endregion


#region PwshSpectreConsole/public/live/Invoke-SpectreScriptBlockQuietly.ps1


function Invoke-SpectreScriptBlockQuietly {
    <#
    .SYNOPSIS
        This function invokes a script block in a background job and returns the output.
        
    .DESCRIPTION
        This is a test function for invoking a script block in a background job inside Invoke-SpectreCommandWithProgress to help with https://github.com/ShaunLawrie/PwshSpectreConsole/issues/7  
        Some commands cause output that interferes with the progress bar, this function is an attempt to suppress that output when all other attempts have failed.

    .EXAMPLE
        # **Example 1**  
        # This example demonstrates how to use this function to suppress all output from a script block so it doesn't break the progress bar.
        
        $result = Invoke-SpectreCommandWithProgress {
            param (
                $Context
            )
            $task1 = $Context.AddTask("Starting a process that generates noise")
            $task1.Increment(50)
            $value = Invoke-SpectreScriptBlockQuietly -Level Quiet -Command {
                Write-Output "Things..."
                Write-Output "And stuff..."
                Write-Error "This is an error"
                Start-Sleep -Seconds 3
                Write-Output "But it shouldn't break progress bar rendering"
            }
            $task1.Increment(50)
            return $value
        }
        Write-SpectreHost "Result: $result"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/live/invoke-spectrescriptblockquietly/')]
    [Reflection.AssemblyMetadata("title", "Invoke-SpectreScriptBlockQuietly")]
    param (
        # The script block to be invoked.
        [scriptblock] $Command,
        # Suppresses the output by varying amounts.
        [ValidateSet("Quiet", "Quieter")]
        [string] $Level = "Quiet"
    )
    try {
        $job = Start-ThreadJob $Command
        $job | Wait-Job | Out-Null

        if ($job.State -eq "Failed") {
            $job | Receive-Job
            throw "Failed to execute script block"
        }
        
        switch ($Level) {
            "Quiet" {
                $output = $job | Receive-Job 2>$null
                return $output
            }
            "Quieter" {
                return
            }
            default {
                throw "Invalid value for Level parameter"
            }
        }
    } finally {
        $job | Stop-Job -ErrorAction SilentlyContinue
        $job | Remove-Job -Force -ErrorAction SilentlyContinue
    }
}


#endregion


#region PwshSpectreConsole/public/live/Wait-SpectreJobs.ps1


function Wait-SpectreJobs {
    <#
    .SYNOPSIS
    Waits for Spectre jobs to complete.

    .DESCRIPTION
    This function waits for Spectre jobs to complete by checking the progress of each job and updating the corresponding task value.
    Adapted from https://key2consulting.com/powershell-how-to-display-job-progress/
    :::note
    This is only used inside `Invoke-SpectreCommandWithProgress` where the Spectre ProgressContext object is exposed.
    :::

    .PARAMETER Context
    The Spectre progress context object.
    [https://spectreconsole.net/api/spectre.console/progresscontext/](https://spectreconsole.net/api/spectre.console/progresscontext/)

    .PARAMETER Jobs
    An array of Spectre jobs which are decorated PowerShell jobs.

    .PARAMETER TimeoutSeconds
    The maximum number of seconds to wait for the jobs to complete. Defaults to 60 seconds.

    .PARAMETER EstimatedDurationSeconds
    The estimated duration of the jobs in seconds. This is used to calculate the progress of the jobs if the job progress is not available.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to add two jobs to a context and wait for them to complete.
    
    Invoke-SpectreCommandWithProgress -ScriptBlock {
        param (
            $Context
        )
        $jobs = @()
        $jobs += Add-SpectreJob -Context $Context -JobName "job 1" -Job (Start-Job { Start-Sleep -Seconds 2 })
        $jobs += Add-SpectreJob -Context $Context -JobName "job 2" -Job (Start-Job { Start-Sleep -Seconds 4 })
        Wait-SpectreJobs -Context $Context -Jobs $jobs
    }
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/live/wait-spectrejobs/')]
    [Reflection.AssemblyMetadata("title", "Wait-SpectreJobs")]
    param (
        [Parameter(Mandatory)]
        [object] $Context,
        [Parameter(Mandatory)]
        [array] $Jobs,
        [int] $TimeoutSeconds = 60,
        [int] $EstimatedDurationSeconds
    )

    $start = Get-Date
    $timeout = (Get-Date).AddSeconds($TimeoutSeconds)

    while (!$Context.IsFinished) {
        if ((Get-Date) -gt $timeout) {
            throw "Timed out waiting for jobs after $TimeoutSeconds seconds"
        }
        $completedJobs = 0
        foreach ($job in $Jobs) {
            # JobState is an Enum. Anything less than [System.Management.Automation.JobState]::Completed (NotStarted, Running) is not 100%
            # https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.jobstate?view=powershellsdk-7.4.0
            if ([System.Management.Automation.JobState]$job.Job.State -ge [System.Management.Automation.JobState]::Completed) {
                $job.Task.Value = 100.0
                $completedJobs++
                continue
            }
            $progress = 0.0
            if ($job.Job.ChildJobs[0].Progress) {
                $progress = $job.Job.ChildJobs[0].Progress | Select-Object -Last 1 -ExpandProperty "PercentComplete"
            } elseif($EstimatedDurationSeconds) {
                $estimatedProgress = ((Get-Date) - $start).TotalSeconds / $EstimatedDurationSeconds * 100
                if($estimatedProgress -gt 99) {
                    # Job is only estimated to be finished, switch to an indeterminate one now
                    $progress = 99
                    if(!$job.Task.IsIndeterminate) {
                        $job.Task.IsIndeterminate = $true
                    }
                } else {
                    $progress = $estimatedProgress
                }
            }
            $job.Task.Value = $progress
        }
        Start-Sleep -Milliseconds 100
    }
}


#endregion


#region PwshSpectreConsole/public/measurement/Get-SpectreLayoutSizes.ps1


function Get-SpectreLayoutSizes {
    <#
    .SYNOPSIS
    Gets the width and height of all of the layouts in a Spectre Console Layout.

    .DESCRIPTION
    The Get-SpectreLayoutSizes function gets the height of a Spectre Console layout object and all of its children. The result is a hashtable where you can access the size details for each layout object by its name.  
    When using sizes you need to be aware that this may include the size of the border if you specified one so you may need to subtract the border size from the total dimensions.

    .PARAMETER Layout
    The root layout to calculate the size for including all of its children.

    .EXAMPLE
    # **Example 1**  
    # This example calculates the heights of all the layouts in a layout tree and tells you how high the content layout will be based on their ratios.

    $layout = New-SpectreLayout -Name "root" -Rows @(
        # Row 1
        (New-SpectreLayout -Name "title" -Ratio 1 -Data ("Title goes here" | Format-SpectrePanel -Expand)),
        # Row 2
        (New-SpectreLayout -Name "body" -Ratio 3 -Columns @(
            # Column 1
            (New-SpectreLayout -Name "left" -Ratio 1 -Data ("Left goes here" | Format-SpectrePanel -Expand)),
            # Column 2
            (New-SpectreLayout -Name "right" -Ratio 2 -Data ("Right goes here" | Format-SpectrePanel -Expand))
        ))
    )

    # Get the sizes of the layouts in the layout tree before populating them with data
    $sizes = $layout | Get-SpectreLayoutSizes
    
    # Subtract the border sizes!
    $titleWidth = $sizes["title"].Width - 2
    $titleHeight = $sizes["title"].Height - 2
    $leftWidth = $sizes["left"].Width - 2
    $leftHeight = $sizes["left"].Height - 2
    $rightWidth = $sizes["right"].Width - 2
    $rightHeight = $sizes["right"].Height - 2

    # Populate the layouts with data that takes up the full height of the layout
    $titleContent = ((1..($titleHeight + 1)) | ForEach-Object { "Title line $_" }) -join "`n"
    $leftContent = ((1..($leftHeight + 1)) | ForEach-Object { "Left line $_" }) -join "`n"
    $rightContent = ((1..($rightHeight + 1)) | ForEach-Object { "Right line $_" }) -join "`n"

    $null = $layout["title"].Update(($titleContent | Format-SpectrePanel -Title "I am $titleWidth x $titleHeight" -Expand))
    $null = $layout["left"].Update(($leftContent | Format-SpectrePanel -Title "I am $leftWidth x $leftHeight" -Expand))
    $null = $layout["right"].Update(($rightContent | Format-SpectrePanel -Title "I am $rightWidth x $rightHeight" -Expand))
    
    $layout | Out-SpectreHost
    
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/measurement/get-spectrelayoutsizes/')]
    [Reflection.AssemblyMetadata("title", "Get-SpectreLayoutSizes")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [Spectre.Console.Layout] $Layout
    )
    
    $width = [Spectre.Console.AnsiConsole]::Console.Profile.Width
    $height = [Spectre.Console.AnsiConsole]::Console.Profile.Height
    
    $size = [Spectre.Console.Size]::new($width, $height)
    $renderOptions = [Spectre.Console.Rendering.RenderOptions]::new(
        [Spectre.Console.AnsiConsole]::Console.Profile.Capabilities,
        $size
    )

    $regions = [PwshSpectreConsole.Extensions.LayoutExtensions]::GetLayoutRegions($Layout, $renderOptions, $renderOptions.ConsoleSize.Width)

    $regionsTable = @{}
    $regions.GetEnumerator() | Foreach-Object {
       $regionsTable[$_.Key] = $_.Value
    }
    
    return $regionsTable
}


#endregion


#region PwshSpectreConsole/public/measurement/Get-SpectreRenderableSize.ps1


function Get-SpectreRenderableSize {
    <#
    .SYNOPSIS
    Gets the width and height of a Spectre Console widget.

    .DESCRIPTION
    The Get-SpectreRenderableSize function gets the height of a Spectre Console renderable object. The width and height is estimated.  
    This method of size calculation is not perfect, but it is a good approximation for most use cases. There are factors outside of the control of this function that can affect the size of the widget once it's rendered to the console.  
    The size of a containing object can influence the size of the widget when it's expandable. If you know the width and height of a container that this widget will be rendered inside you can provide that as a parameter to get a more accurate size.

    .PARAMETER Renderable
    The widget to calculate the size of.

    .PARAMETER ContainerHeight
    The height of the container that the widget will be rendered inside.

    .PARAMETER ContainerWidth
    The width of the container that the widget will be rendered inside.

    .EXAMPLE
    # **Example 1**  
    # This example calculates the height of a small panel
    $panel = "hello`nworld" | Format-SpectrePanel
    $panelSize = $panel | Get-SpectreRenderableSize
    Write-SpectreHost "Panel width: $($panelSize.Width), height: $($panelSize.Height)"
    $panel | Out-SpectreHost
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/measurement/get-spectrerenderablesize/')]
    [Reflection.AssemblyMetadata("title", "Get-SpectreRenderableSize")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [Spectre.Console.Rendering.Renderable] $Renderable,
        [int] $ContainerHeight = [Spectre.Console.AnsiConsole]::Console.Profile.Height,
        [int] $ContainerWidth = [Spectre.Console.AnsiConsole]::Console.Profile.Width
    )
    
    # Use values from the parameters, which will fall back to the console dimensions
    # that have already been validated by Initialize-SpectreConsoleDimensions on module import
    $size = [Spectre.Console.Size]::new($ContainerWidth, $ContainerHeight)
    $renderOptions = [Spectre.Console.Rendering.RenderOptions]::new(
        [Spectre.Console.AnsiConsole]::Console.Profile.Capabilities,
        $size
    )
    $renderOptions.Justification = $null
    $renderOptions.Height = $null

    $render = $Renderable.Render($renderOptions, $ContainerWidth)

    $lines = 0
    $maxLineWidth = 0
    $thisLineWidth = 0
    foreach ($segment in $render) {
        if ($segment.IsLineBreak) {
            if ($thisLineWidth -gt $maxLineWidth) {
                $maxLineWidth = $thisLineWidth
            }
            $thisLineWidth = 0
            $lines++
            continue
        }

        if (!$segment.IsControlCode) {
            $thisLineWidth += $segment.Text.Length
        }
    }

    return @{
        Height = $lines
        Width = $maxLineWidth
    }
}


#endregion


#region PwshSpectreConsole/public/prompts/Read-SpectreConfirm.ps1


function Read-SpectreConfirm {
    <#
    .SYNOPSIS
    Displays a simple confirmation prompt with the option of selecting yes or no and returns a boolean representing the answer. 

    .DESCRIPTION
    Displays a simple confirmation prompt with the option of selecting yes or no. Additional options are provided to display either a success or failure response message in addition to the boolean return value.

    .PARAMETER Message
    The prompt to display to the user. The default value is "Do you like cute animals?".

    .PARAMETER DefaultAnswer
    The default answer to the prompt if the user just presses enter. The default value is "y".

    .PARAMETER ConfirmSuccess
    The text and markup to display if the user chooses yes. If left undefined, nothing will display.

    .PARAMETER ConfirmFailure
    The text and markup to display if the user chooses no. If left undefined, nothing will display.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates a simple confirmation prompt with a success message.
    $answer = Read-SpectreConfirm -Message "Would you like to continue the preview installation of [#7693FF]PowerShell 7?[/]" `
                                  -ConfirmSuccess "Woohoo! The internet awaits your elite development contributions." `
                                  -ConfirmFailure "What kind of monster are you? How could you do this?"
    # Type "y", "↲" to accept the prompt
    Write-Host "Your answer was '$answer'"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/prompts/read-spectreconfirm/')]
    [Reflection.AssemblyMetadata("title", "Read-SpectreConfirm")]
    param (
        [Parameter(Mandatory)]
        [Alias("Title", "Question", "Prompt")]
        [String] $Message,
        [ValidateSet("y", "n", "none")]
        [string] $DefaultAnswer = "y",
        [string] $ConfirmSuccess,
        [string] $ConfirmFailure,
        [int] $TimeoutSeconds,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $Color = $script:AccentColor
    )

    # This is much fiddlier but it exposes the ability to set the color scheme. The confirmationprompt is just a textprompt with two choices hard coded to y/n:
    # https://github.com/spectreconsole/spectre.console/blob/63b940cf0eb127a8cd891a4fe338aa5892d502c5/src/Spectre.Console/Prompts/ConfirmationPrompt.cs#L71
    $confirmationPrompt = [Spectre.Console.TextPrompt[string]]::new($Message)
    $confirmationPrompt = [Spectre.Console.TextPromptExtensions]::AddChoice($confirmationPrompt, "y")
    $confirmationPrompt = [Spectre.Console.TextPromptExtensions]::AddChoice($confirmationPrompt, "n")
    if ($DefaultAnswer -ne "none") {
        $confirmationPrompt = [Spectre.Console.TextPromptExtensions]::DefaultValue($confirmationPrompt, $DefaultAnswer)
    }

    # This is how I added the default colors with Set-SpectreColors so you don't have to keep passing them through and get a consistent TUI color scheme
    $confirmationPrompt.DefaultValueStyle = [Spectre.Console.Style]::new($script:DefaultValueColor)
    $confirmationPrompt.ChoicesStyle = [Spectre.Console.Style]::new($Color)
    $confirmationPrompt.InvalidChoiceMessage = "[red]Please select one of the available options[/]"

    # Invoke-SpectrePromptAsync supports ctrl-c
    $confirmed = (Invoke-SpectrePromptAsync -Prompt $confirmationPrompt -TimeoutSeconds $TimeoutSeconds) -eq "y"

    if (!$confirmed) {
        if (![String]::IsNullOrWhiteSpace($ConfirmFailure)) {
            Write-SpectreHost $ConfirmFailure
        }
    } else {
        if (![String]::IsNullOrWhiteSpace($ConfirmSuccess)) {
            Write-SpectreHost $ConfirmSuccess
        }
    }

    return $confirmed
}


#endregion


#region PwshSpectreConsole/public/prompts/Read-SpectreMultiSelection.ps1


function Read-SpectreMultiSelection {
    <#
    .SYNOPSIS
    Displays a multi-selection prompt using Spectre Console and returns the selected choices.

    .DESCRIPTION
    This function displays a multi-selection prompt using Spectre Console and returns the selected choices. The prompt allows the user to select one or more choices from a list of options. The function supports customizing the title, choices, choice label property, color, and page size of the prompt.

    .PARAMETER Message
    The title of the prompt. Defaults to "What are your favourite [Spectre.Console.Color]?".

    .PARAMETER Choices
    The list of choices to display in the selection prompt. ChoiceLabelProperty is required if the choices are complex objects rather than an array of strings.

    .PARAMETER ChoiceLabelProperty
    If the object is complex then the property of the choice object to use as the label in the selection prompt is required.
    This can be a string property name or a script block that takes the choice object as `$_` and returns a string label.

    .PARAMETER Color
    The color to use for highlighting the selected choices. Defaults to the accent color of the script.

    .PARAMETER PageSize
    The number of choices to display per page. Defaults to 5.

    .PARAMETER AllowEmpty
    Allow the multi-selection to be submitted without any options chosen.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates a multi-selection prompt with a custom title and choices.
    $fruits = Read-SpectreMultiSelection -Message "Select your favourite fruits" `
                                          -Choices @("apple", "banana", "orange", "pear", "strawberry", "durian", "lemon") `
                                          -PageSize 4
    # Type "↓", "<space>", "↓", "↓", "<space>", "↓", "<space>", "↲" to choose banana, pear and strawberry
    Write-SpectreHost "Your favourite fruits are $($fruits -join ', ')"

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates using pipeline input to provide choices for multi-selection.
    $selectedFiles = @("file1.db", "file2.db", "file3.db") | ForEach-Object { [PSCustomObject]@{ Name = $_ } } | Read-SpectreMultiSelection -Message "Select database files to backup" -ChoiceLabelProperty Name
    # Type "<space>", "↓", "<space>", "↲" to select multiple files
    Write-SpectreHost "Selected files: $($selectedFiles.Name -join ', ')"

    .EXAMPLE
    # **Example 3**  
    # This example demonstrates using a scriptblock to generate dynamic labels for complex objects.
    $data = @(
        [PSCustomObject]@{ Name = "Alice"; Age = 30 },
        [PSCustomObject]@{ Name = "Bob"; Age = 25 },
        [PSCustomObject]@{ Name = "Charlie"; Age = 35 }
    )
    $selected = Read-SpectreMultiSelection -Message "Select people" -Choices $data -ChoiceLabelProperty { "$($_.Name) (Age: $($_.Age))" }
    # Type "<space>", "↓", "↓", "<space>", "↲" to select Alice and Charlie
    Write-SpectreHost "Selected: $(($selected | ForEach-Object { $_.Name }) -join ', ')"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/prompts/read-spectremultiselection/')]
    [Reflection.AssemblyMetadata("title", "Read-SpectreMultiSelection")]
    param (
        [Alias("Title", "Question", "Prompt")]
        [string] $Message,
        [Parameter(Mandatory, ValueFromPipeline, Position = 1)]
        [array] $Choices,
        [object] $ChoiceLabelProperty,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $Color = $script:AccentColor,
        [int] $PageSize = 5,
        [int] $TimeoutSeconds,
        [switch] $AllowEmpty
    )
    
    begin {
        $allChoices = @()
    }
    
    process {
        # Collect all choices from pipeline
        if ($null -ne $_) {
            $allChoices += $_
        }
    }
    
    end {
        # Use collected choices from pipeline or parameter choices
        $choicesToUse = if ($allChoices.Count -gt 0) { $allChoices } else { $Choices }
        
        $spectrePrompt = [Spectre.Console.MultiSelectionPrompt[string]]::new()

        $choiceLabels = $choicesToUse
        $choiceObjects = $choicesToUse | Where-Object { $_ -isnot [string] }
        if ($null -ne $choiceObjects -and !$ChoiceLabelProperty) {
            throw "You must specify the ChoiceLabelProperty parameter when using choice groups with complex objects"
        }
        if ($ChoiceLabelProperty -is [scriptblock]) {
            $choiceLabels = $choicesToUse | ForEach-Object -Process $ChoiceLabelProperty
        } elseif ($ChoiceLabelProperty) {
            $choiceLabels = $choicesToUse | Select-Object -ExpandProperty $ChoiceLabelProperty
        }

        $duplicateLabels = $choiceLabels | Group-Object | Where-Object { $_.Count -gt 1 }
        if ($duplicateLabels) {
            throw "You have duplicate labels in your select list, this is ambiguous so a selection cannot be made"
        }

        $spectrePrompt = [Spectre.Console.MultiSelectionPromptExtensions]::AddChoices($spectrePrompt, [string[]]$choiceLabels)
        if ($Message) {
            $spectrePrompt.Title = $Message
        }
        $spectrePrompt.PageSize = $PageSize
        $spectrePrompt.WrapAround = $true
        $spectrePrompt.Required = !$AllowEmpty
        $spectrePrompt.HighlightStyle = [Spectre.Console.Style]::new($Color)
        $spectrePrompt.InstructionsText = "[$($script:DefaultValueColor.ToMarkup())](Press [$($script:AccentColor.ToMarkup())]space[/] to toggle a choice and press [$($script:AccentColor.ToMarkup())]<enter>[/] to submit your answer)[/]"
        $spectrePrompt.MoreChoicesText = "[$($script:DefaultValueColor.ToMarkup())](Move up and down to reveal more choices)[/]"
        $selected = Invoke-SpectrePromptAsync -Prompt $spectrePrompt -TimeoutSeconds $TimeoutSeconds

        if ($ChoiceLabelProperty -is [scriptblock]) {
            $selected = $choicesToUse | Where-Object { $selected -contains (ForEach-Object -InputObject $_ -Process $ChoiceLabelProperty) }
        } elseif ($ChoiceLabelProperty) {
            $selected = $choicesToUse | Where-Object { $selected -contains $_.$ChoiceLabelProperty }
        }

        return $selected
    }
}


#endregion


#region PwshSpectreConsole/public/prompts/Read-SpectreMultiSelectionGrouped.ps1


function Read-SpectreMultiSelectionGrouped {
    <#
    .SYNOPSIS
    Displays a multi-selection prompt with grouped choices and returns the selected choices.

    .DESCRIPTION
    Displays a multi-selection prompt with grouped choices and returns the selected choices. The prompt allows the user to select one or more choices from a list of options. The choices can be grouped into categories, and the user can select choices from each category.

    .PARAMETER Message
    The title of the prompt. The default value is "What are your favourite [Spectre.Console.Color]?".

    .PARAMETER Choices
    An array of choice groups. Each group is a hashtable with two keys: "Name" and "Choices". The "Name" key is a string that represents the name of the group, and the "Choices" key is an array of strings that represents the choices in the group.

    .PARAMETER ChoiceLabelProperty
    The name of the property to use as the label for each choice. If this parameter is not specified, the choices are displayed as strings.
    This can be a string property name or a script block that takes the choice object as `$_` and returns a string label.

    .PARAMETER Color
    The color of the selected choices. The default value is the accent color of the script.

    .PARAMETER PageSize
    The number of choices to display per page. The default value is 10.

    .PARAMETER AllowEmpty
    Allow the multi-selection to be submitted without any options chosen.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates a multi-selection prompt with grouped choices.
    $selected = Read-SpectreMultiSelectionGrouped -Message "Select your favorite colors" -PageSize 8 -Choices @(
        @{
            Name = "Primary Colors"
            Choices = @("Red", "Blue", "Yellow")
        },
        @{
            Name = "Secondary Colors"
            Choices = @("Green", "Orange", "Purple")
        }
    )
    # Type "↓", "<space>", "↓", "↓", "↓", "<space>", "↲" to choose red and all secondary colors
    Write-SpectreHost "Your favourite colors are $($selected -join ', ')"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/prompts/read-spectremultiselectiongrouped/')]
    [Reflection.AssemblyMetadata("title", "Read-SpectreMultiSelectionGrouped")]
    param (
        [Alias("Title", "Question", "Prompt")]
        [string] $Message,
        [Parameter(Mandatory)]
        [array] $Choices,
        [object] $ChoiceLabelProperty,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $Color = $script:AccentColor,
        [int] $PageSize = 10,
        [int] $TimeoutSeconds,
        [switch] $AllowEmpty
    )
    $spectrePrompt = [Spectre.Console.MultiSelectionPrompt[string]]::new()

    $choiceLabels = $Choices.Choices
    $flattenedChoices = $Choices.Choices
    if ($ChoiceLabelProperty -is [scriptblock]) {
        $choiceLabels = $choiceLabels | ForEach-Object -Process $ChoiceLabelProperty
    } elseif ($ChoiceLabelProperty) {
        $choiceLabels = $choiceLabels | Select-Object -ExpandProperty $ChoiceLabelProperty
    }
    $duplicateLabels = $choiceLabels | Group-Object | Where-Object { $_.Count -gt 1 }
    if ($duplicateLabels) {
        throw "You have duplicate labels in your select list, this is ambiguous so a selection cannot be made (even when using choice groups)"
    }

    foreach ($group in $Choices) {
        $choiceObjects = $group.Choices | Where-Object { $_ -isnot [string] }
        if ($null -ne $choiceObjects -and !$ChoiceLabelProperty) {
            throw "You must specify the ChoiceLabelProperty parameter when using choice groups with complex objects"
        }
        $choiceLabels = $group.Choices
        if ($ChoiceLabelProperty -is [scriptblock]) {
            $choiceLabels = $choiceLabels | ForEach-Object -Process $ChoiceLabelProperty
        } elseif ($ChoiceLabelProperty) {
            $choiceLabels = $choiceLabels | Select-Object -ExpandProperty $ChoiceLabelProperty
        }
        $spectrePrompt = [Spectre.Console.MultiSelectionPromptExtensions]::AddChoiceGroup($spectrePrompt, $group.Name, [string[]]$choiceLabels)
    }

    if ($Message) {
        $spectrePrompt.Title = $Message
    }
    $spectrePrompt.PageSize = $PageSize
    $spectrePrompt.WrapAround = $true
    $spectrePrompt.Required = !$AllowEmpty
    $spectrePrompt.HighlightStyle = [Spectre.Console.Style]::new($Color)
    $spectrePrompt.InstructionsText = "[$($script:DefaultValueColor.ToMarkup())](Press [$($script:AccentColor.ToMarkup())]space[/] to toggle a choice and press [$($script:AccentColor.ToMarkup())]<enter>[/] to submit your answer)[/]"
    $spectrePrompt.MoreChoicesText = "[$($script:DefaultValueColor.ToMarkup())](Move up and down to reveal more choices)[/]"
    $selected = Invoke-SpectrePromptAsync -Prompt $spectrePrompt -TimeoutSeconds $TimeoutSeconds

    if ($ChoiceLabelProperty -is [scriptblock]) {
        $selected = $flattenedChoices | Where-Object { $selected -contains (ForEach-Object -InputObject $_ -Process $ChoiceLabelProperty) }
    } elseif ($ChoiceLabelProperty) {
        $selected = $flattenedChoices | Where-Object { $selected -contains $_.$ChoiceLabelProperty }
    }

    return $selected
}


#endregion


#region PwshSpectreConsole/public/prompts/Read-SpectrePause.ps1


function Read-SpectrePause {
    <#
    .SYNOPSIS
    Pauses the script execution and waits for user input to continue.

    .DESCRIPTION
    The Read-SpectrePause function pauses the script execution and waits for user input to continue. It displays a message prompting the user to press the enter key to continue. If the end of the console window is reached, the function clears the message and moves the cursor up to the previous line.

    .PARAMETER Message
    The message to display to the user. The default message is "[default value color]Press [accent color]enter[/] to continue[/]".

    .PARAMETER NoNewline
    Indicates whether to write a newline character before displaying the message. By default, a newline character is written.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to use the Read-SpectrePause function.
    Read-SpectrePause -Message "Press the [red]enter[/] key to continue, when you press it this message will disappear..."
    # Type "↲" to dismiss the message

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to use the Read-SpectrePause function with the AnyKey parameter.
    Read-SpectrePause -Message "Press the [red]ANY[/] key to continue, when you press it this message will disappear..." -AnyKey
    # Type "x" to dismiss the message
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/prompts/read-spectrepause/')]
    [Reflection.AssemblyMetadata("title", "Read-SpectrePause")]
    param (
        [Alias("Title", "Question", "Prompt")]
        [string] $Message = "[$($script:DefaultValueColor.ToMarkup())]Press [$($script:AccentColor.ToMarkup())]<enter>[/] to continue[/]",
        [switch] $AnyKey,
        [switch] $NoNewline
    )

    $enterKey = 13

    # Drain input buffer so enter won't be pressed automatically
    Clear-InputQueue

    $returnLines = 2
    if (!$NoNewline) {
        Write-SpectreHost " "
        $returnLines++
    }
    Write-SpectreHost $Message -NoNewline
    do {
        $key = Read-ConsoleKey
        if($AnyKey) {
            break
        }
    } while (([int]$key.Key) -ne $enterKey)
    Write-SpectreHost ("`r" + (" " * $Message.Length))
    Write-SpectreHost ("`e[${returnLines}A" | Get-SpectreEscapedText)
}


#endregion


#region PwshSpectreConsole/public/prompts/Read-SpectreSelection.ps1


function Read-SpectreSelection {
    <#
    .SYNOPSIS
    Displays a selection prompt using Spectre Console.

    .DESCRIPTION
    This function displays a selection prompt using Spectre Console. The user can select an option from the list of choices provided. The function returns the selected option.  
    With the `-EnableSearch` switch, the user can search for choices in the selection prompt by typing the characters instead of just typing up and down arrows.  

    If you require the option to have the user cancel the selection prompt without making a choice, you will need to add a "None of the above" or "Cancel" option to your choices and handle that in your code.  
    Alternatively you can instruct the user to use Ctrl+C to cancel the prompt, this will cancel the prompt and $null will be returned.

    .PARAMETER Message
    The title of the selection prompt.

    .PARAMETER Choices
    The list of choices to display in the selection prompt. ChoiceLabelProperty is required if the choices are complex objects rather than an array of strings.

    .PARAMETER ChoiceLabelProperty
    If the object is complex then the property of the choice object to use as the label in the selection prompt is required.
    This can be a string property name or a script block that takes the choice object as `$_` and returns a string label.

    .PARAMETER Color
    The color of the selected option in the selection prompt.

    .PARAMETER PageSize
    The number of choices to display per page in the selection prompt.

    .PARAMETER EnableSearch
    If this switch is present, the user can search for choices in the selection prompt by typing the characters instead of just typing up and down arrows.

    .PARAMETER SearchHighlightColor
    The color of the search highlight in the selection prompt. Defaults to a slightly brighter version of the accent color.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates a selection prompt with a custom title and choices.
    $color = Read-SpectreSelection -Message "Select your favorite color" -Choices @("Red", "Green", "Blue") -Color "Green"
    # Type "↓", "↓", "↓", "↓", "↲" to wrap around the list and choose green
    Write-SpectreHost "Your chosen color is '$color'"

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates a selection prompt with a custom title and choices, and search enabled.
    $color = Read-SpectreSelection -Message "Select your favorite color" -Choices @("Blue", "Bluer", "Blue-est") -EnableSearch
    # Type "b", "l", "u", "e", "r", "↲" to choose "Bluer"
    Write-SpectreHost "Your chosen color is '$color'"

    .EXAMPLE
    # **Example 3**  
    # This example demonstrates using pipeline input to provide choices to the selection prompt.
    $selectedFile = @("file1.txt", "file2.txt", "file3.txt") | ForEach-Object { [PSCustomObject]@{ Name = $_ } } | Read-SpectreSelection -Message "Select a file to open" -ChoiceLabelProperty Name
    # Type "↓", "↲" to select the second file
    Write-SpectreHost "Selected file: $($selectedFile.Name)"

    .EXAMPLE
    # **Example 4**  
    # This example demonstrates a selection prompt with a scriptblock to generate dynamic labels for complex objects.
    $data = @(
        [PSCustomObject]@{ Name = "Alice"; Age = 30 },
        [PSCustomObject]@{ Name = "Bob"; Age = 25 },
        [PSCustomObject]@{ Name = "Charlie"; Age = 35 }
    )
    $selected = Read-SpectreSelection -Message "Select a person" -Choices $data -ChoiceLabelProperty { "$($_.Name) (Age: $($_.Age))" }
    # Type "↓", "↲" to select Bob
    Write-SpectreHost "Selected: $($selected.Name)"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/prompts/read-spectreselection/')]
    [Reflection.AssemblyMetadata("title", "Read-SpectreSelection")]
    param (
        [Alias("Title", "Question", "Prompt")]
        [string] $Message,
        [Parameter(Mandatory, ValueFromPipeline, Position = 1)]
        [array] $Choices,
        [object] $ChoiceLabelProperty,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $Color = $script:AccentColor,
        [int] $PageSize = 5,
        [switch] $EnableSearch,
        [int] $TimeoutSeconds,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $SearchHighlightColor = $script:AccentColor.Blend([Spectre.Console.Color]::White, 0.7)
    )
    
    begin {
        $allChoices = @()
    }
    
    process {
        # Collect all choices from pipeline
        if ($null -ne $_) {
            $allChoices += $_
        }
    }
    
    end {
        # Use collected choices from pipeline or parameter choices
        $choicesToUse = if ($allChoices.Count -gt 0) { $allChoices } else { $Choices }
        
        $spectrePrompt = [Spectre.Console.SelectionPrompt[string]]::new()

        $choiceLabels = $choicesToUse
        if ($ChoiceLabelProperty -is [scriptblock]) {
            $choiceLabels = $choicesToUse | ForEach-Object -Process $ChoiceLabelProperty
        } elseif ($ChoiceLabelProperty) {
            $choiceLabels = $choicesToUse | Select-Object -ExpandProperty $ChoiceLabelProperty
        }

        $duplicateLabels = $choiceLabels | Group-Object | Where-Object { $_.Count -gt 1 }
        if ($duplicateLabels) {
            throw "You have duplicate labels in your select list, this is ambiguous so a selection cannot be made"
        }

        $spectrePrompt = [Spectre.Console.SelectionPromptExtensions]::AddChoices($spectrePrompt, [string[]]$choiceLabels)
        if ($Message) {
            $spectrePrompt.Title = $Message
        }
        $spectrePrompt.PageSize = $PageSize
        $spectrePrompt.WrapAround = $true
        $spectrePrompt.HighlightStyle = [Spectre.Console.Style]::new($Color)
        $spectrePrompt.MoreChoicesText = "[$($script:DefaultValueColor.ToMarkup())](Move up and down to reveal more choices)[/]"
        $spectrePrompt.SearchEnabled = $EnableSearch
        $spectrePrompt.SearchHighlightStyle = [Spectre.Console.Style]::new($SearchHighlightColor)

        $selected = Invoke-SpectrePromptAsync -Prompt $spectrePrompt -TimeoutSeconds $TimeoutSeconds

        if ($ChoiceLabelProperty -is [scriptblock]) {
            $selected = $choicesToUse | Where-Object { (ForEach-Object -InputObject $_ -Process $ChoiceLabelProperty) -eq $selected }
        } elseif ($ChoiceLabelProperty) {
            $selected = $choicesToUse | Where-Object -Property $ChoiceLabelProperty -Eq $selected
        }

        return $selected
    }
}


#endregion


#region PwshSpectreConsole/public/prompts/Read-SpectreSelectionGrouped.ps1


function Read-SpectreSelectionGrouped {
    <#
    .SYNOPSIS
    Displays a selection prompt using Spectre Console with groups.

    .DESCRIPTION
    This function displays a selection prompt using Spectre Console. The user can select an option from the list of choices provided. The function returns the selected option.  
    With the `-EnableSearch` switch, the user can search for choices in the selection prompt by typing the characters instead of just typing up and down arrows.

    .PARAMETER Message
    The title of the selection prompt.

    .PARAMETER ChoiceGroups
    The hashtable of choice groups to display in the selection prompt. The hashtable is a collection of string keys for each group name and an array of choices for each group as the values. ChoiceLabelProperty is required if the choices are complex objects rather than an array of strings.

    .PARAMETER ChoiceLabelProperty
    If the object is complex then the property of the choice object to use as the label in the selection prompt is required.
    This can be a string property name or a script block that takes the choice object as `$_` and returns a string label.

    .PARAMETER Color
    The color of the selected option in the selection prompt.

    .PARAMETER PageSize
    The number of choices to display per page in the selection prompt.

    .PARAMETER EnableSearch
    If this switch is present, the user can search for choices in the selection prompt by typing the characters instead of just typing up and down arrows.

    .PARAMETER SearchHighlightColor
    The color of the search highlight in the selection prompt. Defaults to a slightly brighter version of the accent color.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates a selection prompt with a custom title and choices.
    $choices = @{
        "Reds" = @("Crimson", "Ruby", "Scarlet")
        "Greens" = @("Lime", "Emerald", "Jade")
        "Blues" = @("Azure", "Cerulean", "Sapphire")
    }
    $color = Read-SpectreSelectionGrouped -Message "Select your favorite color" -Choices $choices -Color "Green"
    # Type "↓", "↓", "↓", "↓", "↲" to wrap around the list and choose green
    Write-SpectreHost "Your chosen color is '$color'"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/prompts/read-spectreselectiongrouped/')]
    [Reflection.AssemblyMetadata("title", "Read-SpectreSelectionGrouped")]
    param (
        [Alias("Title", "Question", "Prompt")]
        [string] $Message,
        [Parameter(Mandatory)]
        [hashtable] $Choices,
        [object] $ChoiceLabelProperty,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $Color = $script:AccentColor,
        [int] $PageSize = 5,
        [switch] $EnableSearch,
        [int] $TimeoutSeconds,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $SearchHighlightColor = $script:AccentColor.Blend([Spectre.Console.Color]::White, 0.7)
    )
    $spectrePrompt = [Spectre.Console.SelectionPrompt[string]]::new()

    $choiceLabels = $Choices.Values | ForEach-Object { [array]$_ }
    if ($ChoiceLabelProperty -is [scriptblock]) {
        $choiceLabels = $Choices.Values | ForEach-Object { [array]$_ } | ForEach-Object -Process $ChoiceLabelProperty
    } elseif ($ChoiceLabelProperty) {
        $choiceLabels = $Choices.Values | ForEach-Object { [array]$_ } | Select-Object -ExpandProperty $ChoiceLabelProperty
    }

    $duplicateLabels = $choiceLabels | Group-Object | Where-Object { $_.Count -gt 1 }
    if ($duplicateLabels) {
        throw "You have duplicate labels in your select list, this is ambiguous so a selection cannot be made"
    }

    foreach ($key in $Choices.Keys) {
        $groupChoiceLabels = $Choices[$key]
        if ($ChoiceLabelProperty -is [scriptblock]) {
            $groupChoiceLabels = $Choices[$key] | ForEach-Object -Process $ChoiceLabelProperty
        } elseif ($ChoiceLabelProperty) {
            $groupChoiceLabels = $Choices[$key] | Select-Object -ExpandProperty $ChoiceLabelProperty
        }
        $spectrePrompt = [Spectre.Console.SelectionPromptExtensions]::AddChoiceGroup($spectrePrompt, $key, [string[]]$groupChoiceLabels)
    }
    
    if ($Message) {
        $spectrePrompt.Title = $Message
    }
    $spectrePrompt = [Spectre.Console.SelectionPromptExtensions]::Mode($spectrePrompt, [Spectre.Console.SelectionMode]::Leaf)
    $spectrePrompt.PageSize = $PageSize
    $spectrePrompt.WrapAround = $true
    $spectrePrompt.HighlightStyle = [Spectre.Console.Style]::new($Color)
    $spectrePrompt.MoreChoicesText = "[$($script:DefaultValueColor.ToMarkup())](Move up and down to reveal more choices)[/]"
    $spectrePrompt.SearchEnabled = $EnableSearch
    $spectrePrompt.SearchHighlightStyle = [Spectre.Console.Style]::new($SearchHighlightColor)

    $selected = Invoke-SpectrePromptAsync -Prompt $spectrePrompt -TimeoutSeconds $TimeoutSeconds

    if ($ChoiceLabelProperty -is [scriptblock]) {
        $selected = $Choices.Values | ForEach-Object { [array]$_ } | Where-Object { (ForEach-Object -InputObject $_ -Process $ChoiceLabelProperty) -eq $selected }
    } elseif ($ChoiceLabelProperty) {
        $selected = $Choices.Values | ForEach-Object { [array]$_ } | Where-Object -Property $ChoiceLabelProperty -Eq $selected
    }

    return $selected
}


#endregion


#region PwshSpectreConsole/public/prompts/Read-SpectreText.ps1


function Read-SpectreText {
    <#
    .SYNOPSIS
    Prompts the user with a question and returns the user's input.

    .DESCRIPTION
    This function uses Spectre Console to prompt the user with a question and returns the user's input.
    :::caution
    I would advise against this and instead use `Read-Host` because the Spectre Console prompt doesn't have access to the PowerShell session history.  
    Without session history you can't use the up and down arrow keys to navigate through your previous commands.
    This text entry also doesn't allow you to use arrow keys to go back and forwards through the text you're entering.
    :::

    .PARAMETER Message
    The question to prompt the user with.

    .PARAMETER DefaultAnswer
    The default answer if the user does not provide any input.

    .PARAMETER AnswerColor
    The color of the user's answer input. The default behaviour uses the standard terminal text color.

    .PARAMETER AllowEmpty
    If specified, the user can provide an empty answer.

    .PARAMETER Choices
    An array of choices that the user can choose from. If specified, the user will be prompted with a list of choices to choose from, with validation.
    With autocomplete and can tab through the choices.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates a simple text prompt with a default answer.
    $name = Read-SpectreText -Message "What's your name?" -DefaultAnswer "Prefer not to say"
    # Type "↲" to provide no answer
    Write-SpectreHost "Your name is '$name'"

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates a simple text prompt with a default answer and a color.
    $favouriteColor = Read-SpectreText -Message "What's your favorite color?" -DefaultAnswer "pink"
    # Type "orange", "↲" to enter your favourite color
    Write-SpectreHost "Your favourite color is '$favouriteColor'"

    .EXAMPLE
    # **Example 3**  
    # This example demonstrates a simple text prompt with a default answer, a color, and a list of choices.
    $favouriteColor = Read-SpectreText -Message "What's your favorite color?" -AnswerColor "Cyan1" -Choices "Black", "Green", "Magenta", "I'll never tell!"
    # Type "orange", "↲", "magenta", "↲" to enter text that must match a choice in the choices list, orange will be rejected, magenta will be accepted
    Write-SpectreHost "Your favourite color is '$favouriteColor'"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/prompts/read-spectretext/')]
    [Reflection.AssemblyMetadata("title", "Read-SpectreText")]
    param (
        [Parameter(Mandatory)]
        [Alias("Title", "Question", "Prompt")]
        [string] $Message,
        [string] $DefaultAnswer,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $AnswerColor,
        [switch] $AllowEmpty,
        [int] $TimeoutSeconds,
        [string[]] $Choices
    )
    $spectrePrompt = [Spectre.Console.TextPrompt[string]]::new($Message, [System.StringComparer]::InvariantCultureIgnoreCase)
    $spectrePrompt.DefaultValueStyle = [Spectre.Console.Style]::new($script:DefaultValueColor)
    if ($DefaultAnswer) {
        $spectrePrompt = [Spectre.Console.TextPromptExtensions]::DefaultValue($spectrePrompt, $DefaultAnswer)
    }
    if ($AnswerColor) {
        $spectrePrompt.PromptStyle = [Spectre.Console.Style]::new($AnswerColor)
    }
    $spectrePrompt.AllowEmpty = $AllowEmpty
    if ($null -ne $Choices) {
        $spectrePrompt = [Spectre.Console.TextPromptExtensions]::AddChoices($spectrePrompt, $Choices)
    }
    return Invoke-SpectrePromptAsync -Prompt $spectrePrompt -TimeoutSeconds $TimeoutSeconds
}


#endregion


#region PwshSpectreConsole/public/writing/Get-SpectreEscapedText.ps1


function Get-SpectreEscapedText {
    <#
    .SYNOPSIS
    Escapes text for use in Spectre Console.
    [ShaunLawrie/PwshSpectreConsole/issues/5](https://github.com/ShaunLawrie/PwshSpectreConsole/issues/5)

    .DESCRIPTION
    This function escapes text for use where Spectre Console accepts markup. It is intended to be used as a helper function for other functions that output text to the console using Spectre Console which contains special characters that need escaping.
    See [https://spectreconsole.net/markup](https://spectreconsole.net/markup) for more information about the markup language used in Spectre Console.

    .PARAMETER Text
    The text to be escaped.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to escape text for use in Spectre Console.
    $data = "][[][red]]][[/][][]["
    Format-SpectrePanel -Title "Unescaped data" -Data "I want escaped $($data | Get-SpectreEscapedText) [yellow]and[/] [red]unescaped[/] data"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/writing/get-spectreescapedtext/')]
    [Reflection.AssemblyMetadata("title", "Get-SpectreEscapedText")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [string] $Text
    )
    return [Spectre.Console.Markup]::Escape($Text)
}


#endregion


#region PwshSpectreConsole/public/writing/Out-SpectreHost.ps1


function Out-SpectreHost {
    <#
    .SYNOPSIS
    Writes a spectre renderable to the console host.

    .DESCRIPTION
    Out-SpectreHost writes a spectre renderable object to the console host.  
    This function is used to output spectre renderables to the console when you want to avoid the additional newlines that the PowerShell formatter adds.

    .PARAMETER Data
    The data to write to the console.

    .PARAMETER CustomItemFormatter
    The default host customitem formatter has some restrictions, it needs to be one char less wide than when outputting to the standard console or it will wrap.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to write a spectre renderable object to the console host.
    $table = Get-ChildItem | Select-Object Name, Length, LastWriteTime | Format-SpectreTable
    $table | Out-SpectreHost
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/writing/out-spectrehost/')]
    [Reflection.AssemblyMetadata("title", "Out-SpectreHost")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [RenderableTransformationAttribute()]
        [object] $Data,
        [switch] $CustomItemFormatter
    )

    begin {}

    process {
        if ($Data -is [array]) {
            foreach ($dataItem in $Data) {
                Write-AnsiConsole -RenderableObject $dataItem -CustomItemFormatter:$CustomItemFormatter
            }
        } else {
            Write-AnsiConsole -RenderableObject $Data -CustomItemFormatter:$CustomItemFormatter
        }
    }

    end {}
}


#endregion


#region PwshSpectreConsole/public/writing/Write-SpectreCalendar.ps1


function Write-SpectreCalendar {
    <#
    .SYNOPSIS
    Writes a Spectre Console Calendar text to the console.

    .DESCRIPTION
    Writes a Spectre Console Calendar text to the console.

    .PARAMETER Date
    The date to display the calendar for.

    .PARAMETER Alignment
    The alignment of the calendar.

    .PARAMETER Color
    The color of the calendar.

    .PARAMETER Border
    The border of the calendar.

    .PARAMETER Culture
    The culture of the calendar.

    .PARAMETER Events
    The events to highlight on the calendar.
    Takes a hashtable with the date as the key and the event as the value.

    .PARAMETER HideHeader
    Hides the header of the calendar. (Date)

    .PARAMETER PassThru
    Returns the Spectre Calendar object instead of writing it to the console.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to write a calendar to the console.
    Write-SpectreCalendar -Date 2024-07-01 -Events @{'2024-07-10' = 'Beach time!'; '2024-07-20' = 'Barbecue' }

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to write a calendar to the console with some event details.
    $events = @{
        '2024-01-10' = 'Hello World!'
        '2024-01-20' = 'Hello Universe!'
    }
    Write-SpectreCalendar -Date 2024-01-01 -Events $events
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/writing/write-spectrecalendar/')]
    [Reflection.AssemblyMetadata("title", "Write-SpectreCalendar")]
    param (
        [datetime] $Date = [datetime]::Now,
        [ValidateSet([SpectreConsoleJustify], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string] $Alignment = "Left",
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $Color = $script:AccentColor,
        [ValidateSet([SpectreConsoleTableBorder], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string] $Border = "Rounded",
        [cultureinfo] $Culture = [cultureinfo]::CurrentCulture,
        [Hashtable]$Events,
        [Switch] $HideHeader,
        [Switch] $PassThru
    )
    $calendar = [Spectre.Console.Calendar]::new($date)
    $calendar.Border = [Spectre.Console.TableBorder]::$Border
    $calendar.BorderStyle = [Spectre.Console.Style]::new($Color)
    $calendar.Culture = $Culture
    $calendar.HeaderStyle = [Spectre.Console.Style]::new($Color)
    $calendar.HighlightStyle = [Spectre.Console.Style]::new($Color)
    if ($HideHeader) {
        $calendar.ShowHeader = $false
    }

    $eventsTable = $null

    if ($Events) {
        foreach ($calendarEvent in $events.GetEnumerator()) {
            # Calendar events don't appear to support Culture.
            $eventDate = $calendarEvent.Name -as [datetime]
            $calendar = [Spectre.Console.CalendarExtensions]::AddCalendarEvent($calendar, $calendarEvent.value, $eventDate.Year, $eventDate.Month, $eventDate.Day)
        }
        $eventsTable = $calendar.CalendarEvents | Sort-Object -Property Day | Format-SpectreTable -Property Description, Year, Month, Day -Border $Border -Color $Color
        
        # Apply alignment to the events table
        $eventsTable = $eventsTable | Format-SpectreAligned -HorizontalAlignment $Alignment
    }

    if ($Alignment) {
        $calendar = $calendar | Format-SpectreAligned -HorizontalAlignment $Alignment
    }

    $outputData = @($calendar)
    
    if ($eventsTable) {
        $outputData += $eventsTable
    }

    if ($PassThru) {
        return $outputData | Format-SpectreRows
    }
    
    $outputData | Format-SpectreRows | Out-SpectreHost
}


#endregion


#region PwshSpectreConsole/public/writing/Write-SpectreFigletText.ps1


function Write-SpectreFigletText {
    <#
    .SYNOPSIS
    Writes a Spectre Console Figlet text to the console.

    .DESCRIPTION
    This function writes a Spectre Console Figlet text to the console. The text can be aligned to the left, right, or center, and can be displayed in a specified color.

    .PARAMETER Text
    The text to display in the Figlet format.

    .PARAMETER Alignment
    The alignment of the text. The default value is "Left".

    .PARAMETER Color
    The color of the text. The default value is the accent color of the script.

    .PARAMETER FigletFontPath
    The path to the Figlet font file to use. If this parameter is not specified, the default built-in Figlet font is used.
    The figlet font format is usually *.flf, see https://spectreconsole.net/widgets/figlet for more.

    .PARAMETER PassThru
    Returns the Spectre Figlet text object instead of writing it to the console.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to write Figlet text to the console.
    Write-SpectreFigletText -Text "Hello Spectre!" -Alignment "Center" -Color "Red"

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to write Figlet text to the console using a custom Figlet font.
    Write-SpectreFigletText -Text "Whoa?!" -FigletFontPath "..\PwshSpectreConsole.Docs\src\assets\3d.flf"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/writing/write-spectrefiglettext/')]
    [Reflection.AssemblyMetadata("title", "Write-SpectreFigletText")]
    param (
        [string] $Text = "Hello Spectre!",
        [ValidateSet([SpectreConsoleJustify], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string] $Alignment = "Left",
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $Color = $script:AccentColor,
        [string] $FigletFontPath,
        [switch] $PassThru
    )
    $figletFont = Read-FigletFont -FigletFontPath $FigletFontPath
    $figletText = [Spectre.Console.FigletText]::new($figletFont, $Text)
    $figletText.Justification = [Spectre.Console.Justify]::$Alignment
    $figletText.Color = $Color

    if ($PassThru) {
        return $figletText
    }
    
    Write-AnsiConsole $figletText
}


#endregion


#region PwshSpectreConsole/public/writing/Write-SpectreHost.ps1


function Write-SpectreHost {
    <#
    .SYNOPSIS
    Writes a message to the console using Spectre Console markup.

    .DESCRIPTION
    The Write-SpectreHost function writes a message to the console using Spectre Console. It supports ANSI markup and can optionally append a newline character to the end of the message.
    The markup language is defined at [https://spectreconsole.net/markup](https://spectreconsole.net/markup)
    Supported emoji are defined at [https://spectreconsole.net/appendix/emojis](https://spectreconsole.net/appendix/emojis)

    .PARAMETER Message
    The message to write to the console.

    .PARAMETER NoNewline
    If specified, the message will not be followed by a newline character.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to write a message to the console using Spectre Console markup.
    Write-SpectreHost -Message "Hello, [blue underline]world[/]! :call_me_hand:"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/writing/write-spectrehost/')]
    [Reflection.AssemblyMetadata("title", "Write-SpectreHost")]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [object] $Message,
        [switch] $NoNewline,
        [switch] $PassThru,
        [ValidateSet([SpectreConsoleJustify], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string]$Justify = "Left"
    )
    return Write-SpectreHostInternalMarkup $Message -Justify $Justify -PassThru:$PassThru -NoNewline:$NoNewline
}


#endregion


#region PwshSpectreConsole/public/writing/Write-SpectreRule.ps1


function Write-SpectreRule {
    <#
    .SYNOPSIS
    Writes a Spectre horizontal-rule to the console.

    .DESCRIPTION
    The Write-SpectreRule function writes a Spectre horizontal-rule to the console with the specified title, alignment, and color.
    You can control the width of the rule by specifying either the Width or WidthPercent parameter.

    .PARAMETER Title
    The title of the rule.

    .PARAMETER Alignment
    The alignment of the text in the rule. The default value is Left.

    .PARAMETER Color
    The color of the rule. The default value is the accent color of the script.

    .PARAMETER LineColor
    The color of the rule's line. The default value is the default value color of the script.

    .PARAMETER Width
    The width of the rule in characters. If not specified, the rule will span the full width of the console.
    Cannot be used together with WidthPercent.

    .PARAMETER WidthPercent
    The width of the rule as a percentage of the console width. Value must be between 1 and 100.
    Cannot be used together with Width.

    .PARAMETER PassThru
    Returns the Spectre Rule object instead of writing it to the console.

    .EXAMPLE
    # **Example 1**  
    # This example demonstrates how to write a rule to the console.
    Write-SpectreRule -Title "My Rule" -Alignment Center -Color Yellow

    .EXAMPLE
    # **Example 2**  
    # This example demonstrates how to write a rule with a specific width.
    Write-SpectreRule -Title "Fixed Width Rule" -Width 40

    .EXAMPLE
    # **Example 3**  
    # This example demonstrates how to write a rule with a width that's a percentage of the console width.
    Write-SpectreRule -Title "Half Width Rule" -WidthPercent 50 -Alignment Center

    .EXAMPLE
    # **Example 4**
    # This example demonstrates writing a rule by directly providing the title text.
    Write-SpectreRule "Simple Rule Title"
    #>
    [CmdletBinding(HelpUri='https://pwshspectreconsole.com/reference/writing/write-spectrerule/', DefaultParameterSetName = 'Default')]
    [Reflection.AssemblyMetadata("title", "Write-SpectreRule")]
    param (
        [Parameter(ParameterSetName = 'Default', Position = 0, ValueFromPipeline = $true)]
        [Parameter(ParameterSetName = 'FixedWidth', Position = 0, ValueFromPipeline = $true)]
        [Parameter(ParameterSetName = 'PercentWidth', Position = 0, ValueFromPipeline = $true)]
        [string] $Title,
        [ValidateSet([SpectreConsoleJustify], ErrorMessage = "Value '{0}' is invalid. Try one of: {1}")]
        [string] $Alignment = "Left",
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $Color = $script:AccentColor,
        [ColorTransformationAttribute()]
        [ArgumentCompletionsSpectreColors()]
        [Spectre.Console.Color] $LineColor = $script:DefaultValueColor,
        [Parameter(ParameterSetName = 'FixedWidth')]
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Width,
        [Parameter(ParameterSetName = 'PercentWidth')]
        [ValidateRange(1, 100)]
        [int] $WidthPercent,
        [switch] $PassThru
    )
    $rule = [Spectre.Console.Rule]::new()
    if ($Title) {
        $rule.Title = "[$($Color.ToMarkup())]$Title[/]"
    }
    $rule.Style = [Spectre.Console.Style]::new($LineColor)
    $rule.Justification = [Spectre.Console.Justify]::$Alignment

    if ($PassThru) {
        return $rule
    }

    # Handle width customization
    if ($PSCmdlet.ParameterSetName -eq 'FixedWidth') {
        Write-AnsiConsoleWithWidth -RenderableObject $rule -MaxWidth $Width | Out-Host
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'PercentWidth') {
        $consoleWidth = Get-HostWidth
        $calculatedWidth = [Math]::Floor($consoleWidth * ($WidthPercent / 100))
        # Ensure minimum width of 1
        $calculatedWidth = [Math]::Max(1, $calculatedWidth)
        Write-AnsiConsoleWithWidth -RenderableObject $rule -MaxWidth $calculatedWidth | Out-Host
    }
    else {
        Write-AnsiConsole -RenderableObject $rule
    }
}


#endregion


#region PwshSpectreConsole/PwshSpectreConsole.psm1
$script:AccentColor = [Spectre.Console.Color]::Blue
$script:DefaultValueColor = [Spectre.Console.Color]::Grey
$script:DefaultTableHeaderColor = [Spectre.Console.Color]::Default
$script:DefaultTableTextColor = [Spectre.Console.Color]::Default

# For widgets that can be streamed to the console as raw text, prompts/progress widgets do not use this.
# This allows the terminal to process them as text so they can be dumped like:
# PS> $widget = "Hello, World!" | Format-SpectrePanel -Title "My Panel" -Color Blue -Expand
# PS> $widget # uses the default powershell console writer
# PS> $widget > file.txt # redirects as string data to file
# PS> $widget | Out-SpectreHost # uses a dedicated console writer that doesn't pad the object like the default formatter
$script:SpectreConsoleWriter = [System.IO.StringWriter]::new()
$script:SpectreConsoleOutput = [Spectre.Console.AnsiConsoleOutput]::new($script:SpectreConsoleWriter)
$script:SpectreConsoleSettings = [Spectre.Console.AnsiConsoleSettings]::new()
$script:SpectreConsoleSettings.Out = $script:SpectreConsoleOutput
$script:SpectreConsole = [Spectre.Console.AnsiConsole]::Create($script:SpectreConsoleSettings)

# Initialize console dimensions to ensure they're valid (important for CI environments)
Initialize-SpectreConsoleDimensions

# cache the DA1 response.
$script:TerminalSupportsSixel = [PwshSpectreConsole.Terminal.Compatibility]::TerminalSupportsSixel()

$script:SpectreProfile = Get-SpectreProfile
if ($script:SpectreProfile.Unicode -eq $true -or $env:IgnoreSpectreConsoleEncoding) {
    return $script:SpectreConsole
}

if ($env:IgnoreSpectreEncoding -eq $true) {
    return
}
@"
[white]Your terminal host is currently using encoding '$($SpectreProfile.Encoding)' which limits Spectre Console functionality.

To enable UTF-8 output in your terminal, add the following line at the top of your PowerShell `$PROFILE file and restart the terminal:
[Orange1 on Grey15]$('$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()' | Get-SpectreEscapedText)[/]

If you don't want to enable UTF-8, you can suppress this warning with the environment variable [Orange1 on Grey15]`$env:IgnoreSpectreEncoding = `$true[/] instead.

For more details see:
 - https://github.com/ShaunLawrie/PwshSpectreConsole/issues/46
 - https://spectreconsole.net/best-practices#configuring-the-windows-terminal-for-unicode-and-emoji-support
 - https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles[/]
"@ | Format-SpectrePanel -Title "[Orange1] PwshSpectreConsole Warning [/]" -Color OrangeRed1 -Expand | Out-Host
#endregion
