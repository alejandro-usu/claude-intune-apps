<#
.SYNOPSIS
    Intune custom detection script for MATLAB R2026b, Toolboxes edition (MATLAB, Simulink and
    common toolboxes).

.DESCRIPTION
    Reports "installed" (writes to stdout, exits 0) only when all of these are present in
    C:\Program Files\MATLAB\R2026b:
      - bin\matlab.exe
      - licenses\network.lic
      - IntuneProducts.txt listing every product below. Install.ps1 writes it after mpm succeeds.
#>
$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
# Must match the Toolboxes edition in Install.ps1.
$Products = @('MATLAB', 'Simulink', 'Statistics_and_Machine_Learning_Toolbox', 'Optimization_Toolbox',
    'Signal_Processing_Toolbox', 'Image_Processing_Toolbox', 'Control_System_Toolbox',
    'Symbolic_Math_Toolbox', 'Curve_Fitting_Toolbox')

try {
    $root = Join-Path $programFiles 'MATLAB\R2026b'
    if (-not (Test-Path -LiteralPath (Join-Path $root 'bin\matlab.exe'))) { exit 1 }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'licenses\network.lic'))) { exit 1 }
    $marker = Join-Path $root 'IntuneProducts.txt'
    if (-not (Test-Path -LiteralPath $marker)) { exit 1 }
    $installed = @(Get-Content -LiteralPath $marker)
    foreach ($product in $Products) {
        if ($installed -notcontains $product) { exit 1 }
    }

    Write-Output 'MATLAB R2026b (with toolboxes) detected'
    exit 0
} catch {
    exit 1
}
