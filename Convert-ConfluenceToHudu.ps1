<#
    .SYNOPSIS
        TLDR: Run this and enter the path to a confluence export and it will convert it to look very similar to confluence
    .DESCRIPTION
        Essentially, this is designed so that you download an export of your Space(s) as HTML: https://support.atlassian.com/confluence-cloud/docs/export-content-to-word-pdf-html-and-xml/
        Then unzip the export to a folder.
        Then you run this script, paste the path of your exported folder, and wait for the magic to happen.
        Once the script exits, any HTML files prefixed with "CONVERTED - " can be opened as raw HTML and the contents copied.
        The copied HTML can then be pasted into a blank Hudu KB article using the edit HTML function.

        Supported:
        - All standard HTML (Headings, tables, paragraphs, etc.)
        - Images from Confluence will be converted to Base64 and uploaded
        - Any Info, Note, Warning, or Error macros will be converted to their related Hudu callout
        - Any Expand macros will be converted to the <details> html tag - this doesn't look great when editing but will be fine once published
        - Code should be transferred across - it also specifically formats PowerShell as code blocks
        - It also gets rid of some boilerplate confluence export junk
        - It also converts two specific emojis (empty and full checkbox) to Unicode instead of Confluence proprietary

        This should ideally be used in conjunction with https://github.com/mpowelltech/HuduScripts/blob/main/HuduCustomCSS.css for the best effects on things like expand sections.
#>

# Prompt user for root folder
$rootFolder = Read-Host -Prompt 'Enter the root folder path (i.e. C:\Users\Matt\Downloads\ITConfluenceSpace)'
$CurDate = Get-Date -format "yyyy-MM-dd"
Set-Location -Path $rootFolder

# Get all HTML files recursively in the specified folder
$htmlFiles = Get-ChildItem -Path $rootFolder -Filter *.html -File -Recurse

# Loop through each HTML file
foreach ($htmlFile in $htmlFiles) {

    # Read the content of the HTML file
    $htmlContent = Get-Content -Path $htmlFile.FullName -Raw


    #======= Now we need to remove all whitespaces and newlines, except for those within <pre> (code block) tags ======
    # Define a pattern to match everything between <pre> and </pre> tags (including newlines)
    $prePattern = '(?s)<pre\b[^>]*>.*?<\/pre>'
    # Capture all matches of <pre> tags
    $preMatches = [System.Text.RegularExpressions.Regex]::Matches($htmlContent, $prePattern)
    # Create an array to store replaced content
    $replacedContent = @()
    # Replace the content inside <pre> tags with unique placeholders and store them in the array
    foreach ($match in $preMatches) {
        $placeholder = "PRE_TAG_PLACEHOLDER_" + [System.Guid]::NewGuid().ToString("N")
        # Replace $_ with a placeholder before replacing the entire content inside <pre> tags
        $matchValue = $match.Value -replace [regex]::Escape('$'), 'DOLLAR_UNDERSCORE_PLACEHOLDER'
        $replacedContent += $matchValue
        $htmlContent = $htmlContent -replace [regex]::Escape($match.Value), $placeholder
    }
    # Remove newlines outside of <pre> tags
    $htmlContent = $htmlContent -replace "`r`n|`n|`r", " " -replace '>\s+<', '><' -replace '\s+<', ' <' -replace '>\s+', '> '
    # Restore the original content inside <pre> tags
    foreach ($replacement in $replacedContent) {
        # Restore the placeholder back to $_
        $replacement = $replacement -replace 'DOLLAR_UNDERSCORE_PLACEHOLDER', '&#36;'
        $htmlContent = $htmlContent -replace "PRE_TAG_PLACEHOLDER_[a-f0-9]{32}", $replacement
    }



    # Define patterns for confluence macros and corresponding Hudu callouts in a hashtable
    $patternReplacements = @{
        # Info Macro in Confluence -> Info Callout in Hudu
        '<div class="confluence-information-macro confluence-information-macro-.{0,15}"><span class="aui-icon aui-icon-small aui-iconfont-info confluence-information-macro-icon"></span><div class="confluence-information-macro-body">(.*?)<\/div><\/div>' = '<p class="callout callout-info">$1</p>'
        # Note Macro in Confluence -> Info Callout in Hudu
        '<div class="panel" style="background-color: #EAE6FF;border-color: #998DD9;border-width: 1px;"><div class="panelContent" style="background-color: #EAE6FF;">(.*?)<\/div></div>' = '<p class="callout callout-info">$1</p>'
        # Warning Macro in Confluence -> Warning Callout in Hudu
        '<div class="confluence-information-macro confluence-information-macro-.{0,15}"><span class="aui-icon aui-icon-small aui-iconfont-warning confluence-information-macro-icon"></span><div class="confluence-information-macro-body">(.*?)<\/div><\/div>' = '<p class="callout callout-warning">$1</p>'
        # Error macro in Confluence -> Danger Callout in Hudu
        '<div class="confluence-information-macro confluence-information-macro-.{0,15}"><span class="aui-icon aui-icon-small aui-iconfont-error confluence-information-macro-icon"></span><div class="confluence-information-macro-body">(.*?)<\/div><\/div>' = '<p class="callout callout-danger">$1</p>'
        # Success macro in Confluence -> Sucess Callout in Hudu
        '<div class="confluence-information-macro confluence-information-macro-.{0,15}"><span class="aui-icon aui-icon-small aui-iconfont-approve confluence-information-macro-icon"></span><div class="confluence-information-macro-body">(.*?)<\/div><\/div>' = '<p class="callout callout-success">$1</p>'
    }

    # Loop through each pattern and replace in the HTML content
    foreach ($pattern in $patternReplacements.Keys) {
        while ($htmlContent -match $pattern) {
            $originalSelection = $matches[1]
            # Replace nested <p> tags with <br> within the captured group $1
            $modifiedSelection = $originalSelection -replace '<p>(.*?)<\/p>', '$1<br>'
            # Append the specified replacement text
            $modifiedSelection = $patternReplacements[$pattern] -replace '\$1', $modifiedSelection
            # Replace the Confluence information macro with the modified structure
            $htmlContent = $htmlContent -replace [regex]::Escape($matches[0]), $modifiedSelection
        }
    }

    # Replace the expand macro in Confluence with a Hudu <details> HTML tag
    $patternExpander = '(?s)<div id="expander-\d+" class="expand-container">.*?<div id="expander-control-\d+" class="expand-control">.*?<span class="expand-control-text">(.*?)<\/span>.*?<\/div>.*?<div id="expander-content-\d+" class="expand-content">(.*?)<\/div><\/div>'
    $replacementExpander = '<details><summary>$1</summary>$2</details>'
    $htmlContent = $htmlContent -replace $patternExpander, $replacementExpander

    # Replace Images
    $patternImage = '<span class="confluence-embedded-file-wrapper image-(.*?)"><img class="confluence-embedded-image (.*?)" loading="lazy" src="(.*?)" data-image-src="(.*?)" data-height="(.*?)" data-width="(.*?)" data-unresolved-comment-count="(.*?) data-media-type="file"></span>'
    $replacementImage = '<p><strong>IMAGEPLACEHOLDER_FILEPATH:$4,height:$5,width:$6</strong></p>'
    $htmlContent = $htmlContent -replace $patternImage, $replacementImage
    $patternImagePath = '<p><strong>IMAGEPLACEHOLDER_FILEPATH:(.*?),height:(.*?),width:(.*?)</strong></p>'
    # Extract all relative filepaths using regex matches
    $imgPathMatches = [System.Text.RegularExpressions.Regex]::Matches($htmlContent, $patternImagePath)

    foreach ($match in $imgPathMatches) {
        $relativeFilepath = $match.Groups[1].Value
        $height = $match.Groups[2].Value
        $width = $match.Groups[3].Value
        # Read image content as bytes
        $imageContent = Get-Content -Path $relativeFilepath -AsByteStream
        # Convert the image to base64
        $base64Image = [Convert]::ToBase64String($imageContent)
        # Replace the placeholder with the base64 image in the HTML content
        $replacement = '<img class="img-from-confluence" src="data:image/png;base64,' + $base64Image + '" height="' + $height + '" width="' + $width + '"/>'
        $htmlContent = $htmlContent -replace [regex]::Escape($match.Value), $replacement
    }

    # Define other simple patterns and corresponding replacements in a hashtable
    $patternReplacements = @{
        # Replace empty checkbox with emoji
        '<img class="emoticon emoticon-blue-star" data-emoji-id="2b1c" (.*?) alt="\(blue star\)"/>' = '&#11036;'
        # Replace checked checkbox with emoji
        '<img class="emoticon emoticon-blue-star" data-emoji-id="2611" (.*?) alt="\(blue star\)"/>' = '&#9989;'
        # Remove Link above title
        '<div id="breadcrumb-section"><ol id="breadcrumbs"><li class="first"><span><a href="index.html">(.*?)</a></span></li></ol></div>' = ''
        # Replace Author
        '<div class="page-metadata"> Created by <span class=''author''>(.*?)</span>, last modified on (.*?) </div>' = '<div class="page-metadata"> <em>[IMPORTED FROM CONFLUENCE on {0}. Originally created by <span class=''author''>$1</span>, last modified on $2]</em></div>' -f $CurDate
        # Replace PowerShell Code Blocks
        '<pre class="syntaxhighlighter-pre" data-syntaxhighlighter-params="brush: powershell; gutter: false; theme: Confluence" data-theme="Confluence">' = '<pre class="language-powershell">'
        # Get rid of attachments section at the bottom of the page
        '<div class="pageSection group"><div class="pageSectionHeader"><h2 id="attachments" class="pageSectionTitle">Attachments:</h2></div>.*<a href="http://www.atlassian.com/">Atlassian</a></div></section></div></div>' = ''
        # Add space in TOC
        '<li><span class=''TOCOutline''>(.*?)</span>' = '<li><span class=''TOCOutline''>$1. </span>'
    }

    # Loop through each pattern and replace in the HTML content
    foreach ($pattern in $patternReplacements.Keys) {
        $replacement = $patternReplacements[$pattern]
        $htmlContent = $htmlContent -replace $pattern, $replacement
    }

    # Set the filename
    $convertedFilePath = $htmlFile.FullName -replace '\.html$', '-CONVERTED.html'
    # Define a pattern to extract the title text from HTML
    $patternTitle = '<title>(.*?):(.*?)<\/title>'
    # Use regex to extract the title text
    $titleMatches = [regex]::Matches($htmlContent, $patternTitle)
    # Check if any matches were found
    if ($titleMatches.Count -gt 0) {
        # Get the title text from the match
        $titleText = $titleMatches[0].Groups[2].Value
        $sanitizedTitle = $titleText -replace '[^\w\s-]', '' -replace '\s+', '-' -replace '^-+|-+$'
        # Set the path for the new converted file
        $convertedFilePath = "CONVERTED - " + $sanitizedTitle + ".html"
    } else {
        Write-Host "No title text found in the HTML file." + $htmlFile.FullName 
    }

    # Write the modified content to the new file
    $htmlContent | Set-Content -Path $convertedFilePath

    # Output the path of the converted file
    Write-Host "Coverted file: " + $convertedFilePath
}
