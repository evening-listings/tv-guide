# Builds a small XMLTV guide containing only the channels listed in channel-ids.txt.
# Runs on GitHub Actions every day; also runs on Windows PowerShell 5.1 for local testing.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$work = Join-Path $root 'work'
New-Item -ItemType Directory -Force $work | Out-Null
$curl = if ($IsLinux) { 'curl' } else { 'curl.exe' }

$sources = [ordered]@{
  'iptv-us'  = 'https://iptv-epg.org/files/epg-us.xml.gz'
  'iptv-gb'  = 'https://iptv-epg.org/files/epg-gb.xml.gz'
  'iptv-au'  = 'https://iptv-epg.org/files/epg-au.xml.gz'
  'iptv-nz'  = 'https://iptv-epg.org/files/epg-nz.xml.gz'
  'iptv-sg'  = 'https://iptv-epg.org/files/epg-sg.xml.gz'
  'iptv-jp'  = 'https://iptv-epg.org/files/epg-jp.xml.gz'
  'iptv-kr'  = 'https://iptv-epg.org/files/epg-kr.xml.gz'
  'iptv-tw'  = 'https://iptv-epg.org/files/epg-tw.xml.gz'
  'iptv-in'  = 'https://iptv-epg.org/files/epg-in.xml.gz'
  'iptv-tr'  = 'https://iptv-epg.org/files/epg-tr.xml.gz'
  'iptv-fr'  = 'https://iptv-epg.org/files/epg-fr.xml.gz'
  'iptv-de'  = 'https://iptv-epg.org/files/epg-de.xml.gz'
  'iptv-br'  = 'https://iptv-epg.org/files/epg-br.xml.gz'
  'iptv-id'  = 'https://iptv-epg.org/files/epg-id.xml.gz'
  'mjh-nz'   = 'https://i.mjh.nz/nz/epg.xml.gz'
  'mjh-au'   = 'https://i.mjh.nz/au/all/epg.xml.gz'
  'pluto-us' = 'https://i.mjh.nz/PlutoTV/us.xml.gz'
  'pluto-gb' = 'https://i.mjh.nz/PlutoTV/gb.xml.gz'
  'roku-all' = 'https://i.mjh.nz/Roku/all.xml.gz'
}

$want = @{}
foreach ($l in [IO.File]::ReadAllLines((Join-Path $root 'channel-ids.txt'))) { $id = $l.Trim(); if ($id) { $want[$id] = 1 } }
"channel ids: $($want.Count)"

$now  = [DateTime]::UtcNow
$from = $now.AddHours(-12).ToString('yyyyMMddHHmmss')
$to   = $now.AddDays(5).ToString('yyyyMMddHHmmss')
$xml  = Join-Path $root 'tv-guide.xml'
$w = New-Object IO.StreamWriter($xml, $false, (New-Object Text.UTF8Encoding($false)))
$w.WriteLine('<?xml version="1.0" encoding="UTF-8"?>')
$w.WriteLine('<tv generator-info-name="tv-guide">')

$seen = @{}; $progs = 0; $failed = @()
$settings = New-Object Xml.XmlReaderSettings
$settings.DtdProcessing = 'Ignore'; $settings.IgnoreWhitespace = $true; $settings.CheckCharacters = $false

foreach ($k in $sources.Keys) {
  $f = Join-Path $work "$k.xml.gz"
  $code = & $curl -sL --retry 3 --retry-delay 5 -m 240 -o $f -w '%{http_code}' $sources[$k]
  if ($code -ne '200' -or -not (Test-Path $f) -or (Get-Item $f).Length -lt 500) { $failed += $k; "$k : download failed ($code)"; continue }
  $c0 = $seen.Count; $p0 = $progs
  try {
    $fs = [IO.File]::OpenRead($f)
    $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Decompress)
    $xr = [Xml.XmlReader]::Create($gz, $settings)
    [void]$xr.MoveToContent()
    while (-not $xr.EOF) {
      if ($xr.NodeType -eq 'Element' -and $xr.Name -eq 'channel') {
        $id = $xr.GetAttribute('id')
        if ($want.ContainsKey($id) -and -not $seen.ContainsKey($id)) { $seen[$id] = $k; $w.WriteLine($xr.ReadOuterXml()) } else { $xr.Skip() }
      } elseif ($xr.NodeType -eq 'Element' -and $xr.Name -eq 'programme') {
        $id = $xr.GetAttribute('channel')
        if ($seen.ContainsKey($id) -and $seen[$id] -eq $k) {
          $st = ($xr.GetAttribute('start') -split ' ')[0]
          if ($st -ge $from -and $st -le $to) { $w.WriteLine($xr.ReadOuterXml()); $progs++ } else { $xr.Skip() }
        } else { $xr.Skip() }
      } else { [void]$xr.Read() }
    }
    $xr.Close(); $gz.Close(); $fs.Close()
  } catch { $failed += $k; "$k : parse stopped: $($_.Exception.Message)" }
  "{0,-9} +channels={1} +programmes={2}" -f $k, ($seen.Count - $c0), ($progs - $p0)
  Remove-Item $f -ErrorAction SilentlyContinue
}
$w.WriteLine('</tv>'); $w.Close()
"guide: channels=$($seen.Count)/$($want.Count) programmes=$progs failed=[$($failed -join ',')]"

# A bad day must not replace a good guide: failing here keeps yesterday's published file.
if ($progs -lt 5000) { throw "Only $progs programmes; refusing to publish." }

$gzPath = Join-Path $root 'tv-guide.xml.gz'
$in = [IO.File]::OpenRead($xml); $out = [IO.File]::Create($gzPath)
$zip = New-Object IO.Compression.GZipStream($out, [IO.Compression.CompressionLevel]::Optimal)
$in.CopyTo($zip); $zip.Close(); $out.Close(); $in.Close()
"gz size: $([int]((Get-Item $gzPath).Length / 1KB)) KB"
