param(
    [Parameter(Mandatory=$true)][ValidatePattern('^COM[1-9][0-9]*$')][string]$Port,
    [switch]$Dtr
)
$ErrorActionPreference = 'Stop'
$serial = [System.IO.Ports.SerialPort]::new($Port, 115200, 'None', 8, 'One')
try {
    $serial.ReadTimeout = 100
    $serial.WriteTimeout = 1000
    $serial.Handshake = 'None'
    $serial.DtrEnable = $Dtr.IsPresent
    $serial.Open()
    $serial.DiscardInBuffer()
    $buffer = [byte[]]::new(256)
    [Console]::WriteLine('OK')
    while ($null -ne ($request = [Console]::ReadLine())) {
        if ($request -eq 'R') {
            try {
                $size = $serial.Read($buffer, 0, $buffer.Length)
                [Console]::WriteLine([Convert]::ToBase64String($buffer, 0, $size))
            } catch [TimeoutException] {
                [Console]::WriteLine('')
            }
        } elseif ($request.StartsWith('W ')) {
            $bytes = [Convert]::FromBase64String($request.Substring(2))
            $serial.Write($bytes, 0, $bytes.Length)
            [Console]::WriteLine('OK')
        } else {
            throw 'Invalid serial helper request'
        }
    }
} finally {
    $serial.Dispose()
}
