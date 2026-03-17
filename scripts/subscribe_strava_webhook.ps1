# One-time: create Strava webhook subscription.
# Prereqs: Your backend is deployed and exposes the webhook URL. The verify token
# must match your backend env (e.g. STRAVA_VERIFY_TOKEN on Vercel). Do not commit
# ClientSecret; pass it at invocation only.

param(
    [Parameter(Mandatory=$true)]
    [string]$VerifyToken,
    [Parameter(Mandatory=$true)]
    [string]$ClientSecret,
    [Parameter(Mandatory=$true)]
    [string]$ClientId,
    [Parameter(Mandatory=$true)]
    [string]$CallbackUrl
)

# Strava requires application/x-www-form-urlencoded (see Strava webhook docs)
function Encode-UriComponent { param([string]$s) [System.Net.WebUtility]::UrlEncode($s) }
$body = "client_id=$ClientId&client_secret=$(Encode-UriComponent $ClientSecret)&callback_url=$(Encode-UriComponent $CallbackUrl)&verify_token=$(Encode-UriComponent $VerifyToken)"

try {
    $resp = Invoke-RestMethod -Uri "https://www.strava.com/api/v3/push_subscriptions" `
        -Method Post `
        -Body $body `
        -ContentType "application/x-www-form-urlencoded"
    Write-Host "Subscription created. Id: $($resp.id)"
} catch {
    Write-Host "Error: $_"
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        Write-Host $reader.ReadToEnd()
    }
    exit 1
}

