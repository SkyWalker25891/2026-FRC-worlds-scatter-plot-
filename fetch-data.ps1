param(
    [string]$OutputJson = "data.json",
    [string]$OutputJs = "data.js"
)

$ErrorActionPreference = "Stop"

$divisions = @(
    @{ key = "2026arc"; name = "Archimedes" },
    @{ key = "2026cur"; name = "Curie" },
    @{ key = "2026dal"; name = "Daly" },
    @{ key = "2026gal"; name = "Galileo" },
    @{ key = "2026hop"; name = "Hopper" },
    @{ key = "2026joh"; name = "Johnson" },
    @{ key = "2026mil"; name = "Milstein" },
    @{ key = "2026new"; name = "Newton" }
)

function Get-TeamListFromTbaHtml {
    param(
        [string]$Html
    )

    $teamMatches = [regex]::Matches($Html, 'href="/team/(\d+)(?:/\d+)?"')
    return @(
        $teamMatches |
            ForEach-Object { [int]$_.Groups[1].Value } |
            Sort-Object -Unique
    )
}

function Invoke-CurlWithRetry {
    param(
        [string]$Url,
        [int]$Attempts = 5,
        [int]$DelaySeconds = 2
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
            if ($response.Content) {
                return $response.Content
            }
        } catch {
            if ($attempt -eq $Attempts) {
                throw
            }
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    throw "Failed to fetch $Url after $Attempts attempts"
}

function Get-StatboticsTeamEvent {
    param(
        [int]$Team,
        [string]$EventKey,
        [int]$Attempts = 5,
        [int]$DelaySeconds = 2
    )

    $url = "https://api.statbotics.io/v3/team_event/$Team/$EventKey"
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            return Invoke-RestMethod -Uri $url
        } catch {
            if ($attempt -eq $Attempts) {
                throw
            }
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

$allDivisions = foreach ($division in $divisions) {
    $eventKey = $division.key
    $eventUrl = "https://www.thebluealliance.com/event/$eventKey"

    Write-Host "Fetching team list from The Blue Alliance for $($division.name) ($eventKey)..."
    $tbaHtml = Invoke-CurlWithRetry -Url $eventUrl
    $teams = Get-TeamListFromTbaHtml -Html $tbaHtml

    if (-not $teams -or $teams.Count -eq 0) {
        throw "No teams found on $eventUrl"
    }

    Write-Host "Found $($teams.Count) teams. Fetching Statbotics team-event records..."
    $points = foreach ($team in $teams) {
        $entry = Get-StatboticsTeamEvent -Team $team -EventKey $eventKey
        $breakdown = $entry.epa.breakdown

        [pscustomobject]@{
            team = [int]$entry.team
            team_name = [string]$entry.team_name
            teleop_points = [math]::Round([double]$breakdown.teleop_points, 2)
            auto_points = [math]::Round([double]$breakdown.auto_points, 2)
            endgame_points = [math]::Round([double]$breakdown.endgame_points, 2)
            auto_endgame_points = [math]::Round(([double]$breakdown.auto_points + [double]$breakdown.endgame_points), 2)
            total_points = [math]::Round([double]$breakdown.total_points, 2)
            statbotics_url = "https://www.statbotics.io/team/$($entry.team)"
            tba_url = "https://www.thebluealliance.com/team/$($entry.team)"
            search = "$($entry.team) $($entry.team_name)".ToLowerInvariant()
        }
    }

    [pscustomobject]@{
        key = $eventKey
        name = $division.name
        short_name = $division.name
        tba_url = $eventUrl
        statbotics_url = "https://api.statbotics.io/v3/event/$eventKey"
        team_count = $points.Count
        points = @($points | Sort-Object total_points -Descending)
    }
}

$payload = [pscustomobject]@{
    championship = [pscustomobject]@{
        key = "2026cmptx"
        name = "2026 FRC World Championship - Houston"
        generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        source_notes = @(
            "Team lists scraped from The Blue Alliance division event pages",
            "EPA breakdown values fetched from Statbotics team_event endpoints",
            "Chart uses teleop_points on X and auto_points + endgame_points on Y"
        )
        sources = @(
            "https://www.thebluealliance.com/event/2026cmptx",
            "https://www.thebluealliance.com/event/{division_event_key}",
            "https://api.statbotics.io/v3/team_event/{team}/{division_event_key}"
        )
    }
    divisions = @($allDivisions)
}

$json = $payload | ConvertTo-Json -Depth 8
Set-Content -LiteralPath $OutputJson -Value $json -Encoding UTF8
Set-Content -LiteralPath $OutputJs -Value ("window.CHAMPS_2026_DATA = " + $json + ";") -Encoding UTF8

Write-Host "Wrote $OutputJson and $OutputJs"
