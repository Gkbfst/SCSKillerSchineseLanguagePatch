# SCSKiller 汉化补丁 —— 直接改写程序集里的字符串（不重新编译，不改 IL 逻辑）
# 原理：.NET 程序集的用户字符串存放在 PE 元数据的 #US 堆里，#US 堆条目的长度前缀可控。
#       本脚本把每条原文替换为等长的中文（不足处用空格补齐），因此堆结构、偏移和所有引用
#       都保持不变，程序集大小也不变，只是文字变了。
param(
    [string]$AppDir = '',
    [switch]$Revert,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$targets = 'SCSKiller.dll', 'SCSKiller.Core.dll', 'SCSKiller.Ui.Models.dll'

function Say($msg, $color = 'Gray') { if (-not $Quiet) { Write-Host $msg -ForegroundColor $color } }

function Find-AppDir([string]$start) {
    $candidates = @()
    if ($start) { $candidates += $start }
    $candidates += $here
    foreach ($c in @($candidates)) {
        foreach ($sub in @('', 'current')) {
            $d = if ($sub) { Join-Path $c $sub } else { $c }
            if (Test-Path (Join-Path $d 'SCSKiller.dll')) { return (Resolve-Path $d).Path }
        }
    }
    foreach ($root in @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        foreach ($sub in @('SCSKiller\current', 'SCSKiller')) {
            $d = Join-Path $root $sub
            if (Test-Path (Join-Path $d 'SCSKiller.dll')) { return (Resolve-Path $d).Path }
        }
    }
    return $null
}

$dir = Find-AppDir $AppDir
if (-not $dir) {
    Say '找不到 SCSKiller：请把本补丁放到 SCSKiller.exe 所在的文件夹（或 current 文件夹）里再运行，' 'Red'
    Say '或者运行：一键汉化.bat "D:\你的\SCSKiller\current"' 'Red'
    exit 1
}
Say "程序目录：$dir" 'Cyan'

# 1. 还原
if ($Revert) {
    $n = 0
    foreach ($t in $targets) {
        $f = Join-Path $dir $t
        $bak = "$f.en.bak"
        if (Test-Path $bak) { Copy-Item $bak $f -Force; $n++ }
    }
    if ($n) { Say "已还原英文：$n 个文件" 'Green' } else { Say '没有找到备份，无法还原（重新下载官方版本即可）' 'Yellow' }
    exit 0
}

# 2. 载入译表
$tableFile = Join-Path $here 'translations.json'
if (-not (Test-Path $tableFile)) { Say '缺少 translations.json，无法汉化' 'Red'; exit 1 }
$rows = Get-Content $tableFile -Raw -Encoding UTF8 | ConvertFrom-Json
# 大小写敏感（区分 Play / play），且不用 @{} 以免名为 "keys" 的字符串遮住 .Keys 属性
$table = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
foreach ($r in $rows) { if ($r.en -and $r.zh) { $table[$r.en] = $r.zh } }
Say ("译表条目：{0}" -f $table.Count) 'DarkGray'

# 1.4.5 起，部分文本同时被当作布局标识使用（列宽共享组名、样式类名、InfoBar 级别等），
# Avalonia 会校验这些值，必须是 ASCII 标识符，因此保持英文。
$skipTable = @{
    'SCSKiller.dll' = @(
        'Shaders', 'Pipelines', 'Cache', 'Time', 'Status', 'Filters', 'Scan',
        'Natural', 'Clear', 'Search', 'Details', 'Priority', 'Error', 'Warning',
        'Narrow', 'Stacked', 'Loose', 'Cards', 'Table', 'Columns', 'Rows', 'Split', 'Side'
    )
    'SCSKiller.Core.dll' = @('Priority')
}

# 3. PE / 元数据解析
function Get-Offsets([byte[]]$b) {
    $e = [BitConverter]::ToInt32($b, 0x3C)
    if ($b[$e] -ne 0x50 -or $b[$e + 1] -ne 0x45) { throw '不是有效的 PE 文件' }
    $coff = $e + 4
    $nsec = [BitConverter]::ToUInt16($b, $coff + 2)
    $optSize = [BitConverter]::ToUInt16($b, $coff + 16)
    $opt = $coff + 20
    $magic = [BitConverter]::ToUInt16($b, $opt)
    $dd = $opt + $(if ($magic -eq 0x10b) { 96 } else { 112 })
    $cliRva = [BitConverter]::ToUInt32($b, $dd + 14 * 8)
    $secs = @()
    for ($i = 0; $i -lt $nsec; $i++) {
        $s = $opt + $optSize + 40 * $i
        $secs += , @{
            va = [BitConverter]::ToUInt32($b, $s + 12)
            vsize = [BitConverter]::ToUInt32($b, $s + 8)
            rawsize = [BitConverter]::ToUInt32($b, $s + 16)
            raw = [BitConverter]::ToUInt32($b, $s + 20)
        }
    }
    $rva2off = {
        param($rva)
        foreach ($s in $secs) {
            $span = [Math]::Max($s.vsize, $s.rawsize)
            if ($rva -ge $s.va -and $rva -lt $s.va + $span) { return ($rva - $s.va + $s.raw) }
        }
        throw ("RVA 0x{0:X} 未映射" -f $rva)
    }
    $cli = & $rva2off $cliRva
    $mdRva = [BitConverter]::ToUInt32($b, $cli + 8)
    $md = & $rva2off $mdRva
    if ([Text.Encoding]::ASCII.GetString($b, $md, 4) -ne 'BSJB') { throw '元数据签名不正确' }
    $verLen = [BitConverter]::ToUInt32($b, $md + 12)
    $o = $md + 16 + ((($verLen + 3) -band (-bnot 3)))
    $n = [BitConverter]::ToUInt16($b, $o + 2)
    $o += 4
    $us = -1; $usSize = 0
    for ($i = 0; $i -lt $n; $i++) {
        $soff = [BitConverter]::ToUInt32($b, $o)
        $ssize = [BitConverter]::ToUInt32($b, $o + 4)
        $p = $o + 8
        while ($b[$p] -ne 0) { $p++ }
        $name = [Text.Encoding]::ASCII.GetString($b, $o + 8, $p - ($o + 8))
        $o = $p + 1
        $o = ($o + 3) -band (-bnot 3)
        if ($name -eq '#US') { $us = $md + $soff; $usSize = $ssize }
    }
    if ($us -lt 0) { throw '找不到 #US 堆' }
    return @{ us = $us; size = $usSize; md = $md }
}

function Read-CInt([byte[]]$b, [int]$p) {
    $x = [int]$b[$p]
    if (($x -band 0x80) -eq 0) { return @($x, 1) }
    if (($x -band 0xC0) -eq 0x80) {
        $v = ((($x -band 0x3F) -shl 8) -bor [int]$b[$p + 1])
        return @($v, 2)
    }
    $v = ((($x -band 0x1F) -shl 24) -bor ([int]$b[$p + 1] -shl 16) -bor ([int]$b[$p + 2] -shl 8) -bor [int]$b[$p + 3])
    return @($v, 4)
}

function Read-Heap([byte[]]$b, $layout) {
    $entries = [System.Collections.Generic.Dictionary[string, hashtable]]::new([StringComparer]::Ordinal)
    $end = $layout.us + $layout.size
    $p = $layout.us + 1
    while ($p -lt $end) {
        $r = Read-CInt $b $p
        $len = $r[0]; $nb = $r[1]
        if ($len -eq 0) { $p += $nb; continue }
        if ($p + $nb + $len -gt $end) { break }
        $units = [int](($len - 1) / 2)
        $text = [Text.Encoding]::Unicode.GetString($b, $p + $nb, $len - 1)
        $entries[$text] = @{ off = ($p - $layout.us) + $nb; units = $units }
        $p += $nb + $len
    }
    return $entries
}

# 4. 逐个文件打补丁
$running = Get-Process -Name 'SCSKiller' -ErrorAction SilentlyContinue
if ($running) {
    Say 'SCSKiller 正在运行，请先退出再汉化（否则文件被占用，写入会失败）。' 'Red'
    exit 1
}

$total = 0
foreach ($t in $targets) {
    $file = Join-Path $dir $t
    if (-not (Test-Path $file)) { continue }
    $b = [IO.File]::ReadAllBytes($file)
    $layout = Get-Offsets $b
    $entries = Read-Heap $b $layout
    if ($env:SCSKILLER_PATCH_DEBUG) { Say ("  {0}: #US 0x{1:X} 长度 {2}，解析出 {3} 条字符串" -f $t, $layout.us, $layout.size, $entries.Count) 'DarkGray' }

    $applied = 0; $tooLong = 0
    $skip = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($skipTable.ContainsKey($t)) { foreach ($s in $skipTable[$t]) { [void]$skip.Add($s) } }
    foreach ($kv in $entries.GetEnumerator()) {
        $k = $kv.Key
        if ($skip.Contains($k)) { continue }
        if (-not $table.ContainsKey($k)) { continue }
        $zh = $table[$k]
        $e = $kv.Value
        if ($zh.Length -gt $e.units) { $tooLong++; continue }
        $padded = $zh + (' ' * ($e.units - $zh.Length))
        $bytes = [Text.Encoding]::Unicode.GetBytes($padded)
        [Array]::Copy($bytes, 0, $b, $layout.us + $e.off, $bytes.Length)
        $applied++
    }

    if ($applied -gt 0) {
        $bak = "$file.en.bak"
        if (-not (Test-Path $bak)) { Copy-Item $file $bak -Force }
        [IO.File]::WriteAllBytes($file, $b)
        Say ("{0,-26} 已汉化 {1,4} 条{2}" -f $t, $applied, $(if ($tooLong) { "，过长跳过 $tooLong" } else { '' })) 'Green'
        $total += $applied
    } else {
        Say ("{0,-26} 没有可匹配的文本（版本不同？）" -f $t) 'Yellow'
    }
}

if ($total -gt 0) {
    Say "完成：共替换 $total 条文本。重新启动 SCSKiller 即可看到中文。" 'Green'
    Say '提示：程序自动更新后文件会被覆盖，需要重新运行本补丁。' 'DarkGray'
} else {
    Say '没有写入任何内容。' 'Yellow'
}
