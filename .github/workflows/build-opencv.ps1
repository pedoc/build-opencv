# PowerShell script to build OpenCV on Windows

# Exit on error
$ErrorActionPreference = "Stop"

# Variables
$OpenCVVersion = "4.5.5"
$OpenCVVersionNoDot = $OpenCVVersion -replace '\.', ''
$OpenCVContribVersion = "4.x"
$InstallDir = "C:\opencv_install"
$BuildDir = "$env:USERPROFILE\opencv_build"
$NumJobs = [Environment]::ProcessorCount

# Create build directory
if (-Not (Test-Path -Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
}

Write-Host "Preparing dependencies..."

# Install dependencies using Chocolatey (ensure Chocolatey is installed)
choco install -y git cmake python3 wget 7zip make ninja-build

# Function to install BellSoft JDK 8
function Install-BellSoftJDK8 {
    $Url = "https://download.bell-sw.com/java/8u432+7/bellsoft-jdk8u432+7-windows-amd64.zip"
    $Archive = "$env:TEMP\bellsoft-jdk8u432+7-windows-amd64.zip"
    $InstallDir = "C:\Program Files\BellSoft\JDK8"

    if (Test-Path -Path $InstallDir) {
        Write-Host "BellSoft JDK 8 is already installed at $InstallDir"
        return
    }

    Write-Host "Installing BellSoft JDK 8..."
    Invoke-WebRequest -Uri $Url -OutFile $Archive
    Expand-Archive -Path $Archive -DestinationPath $InstallDir -Force

    # Set environment variables
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $InstallDir, [EnvironmentVariableTarget]::Machine)
    [Environment]::SetEnvironmentVariable("Path", "$($env:Path);$InstallDir\bin", [EnvironmentVariableTarget]::Machine)

    Write-Host "BellSoft JDK 8 installed at $InstallDir"
    & java -version
}

# Function to install Apache Ant
function Install-Ant {
    $AntVersion = "1.10.15"
    $AntUrl = "https://downloads.apache.org/ant/binaries/apache-ant-$AntVersion-bin.zip"
    $InstallDir = "C:\Program Files\Ant"

    if (Test-Path -Path $InstallDir) {
        Write-Host "Apache Ant is already installed at $InstallDir"
        return
    }

    Write-Host "Installing Apache Ant..."
    $Archive = "$env:TEMP\apache-ant-$AntVersion-bin.zip"
    Invoke-WebRequest -Uri $AntUrl -OutFile $Archive
    Expand-Archive -Path $Archive -DestinationPath $InstallDir -Force

    # Set environment variables
    [Environment]::SetEnvironmentVariable("ANT_HOME", $InstallDir, [EnvironmentVariableTarget]::Machine)
    [Environment]::SetEnvironmentVariable("Path", "$($env:Path);$InstallDir\bin", [EnvironmentVariableTarget]::Machine)

    Write-Host "Apache Ant installed at $InstallDir"
    & ant -version
}

# Function to install Python 3.8
function Install-Python38 {
    $PythonVersion = "3.8.2"
    $PythonUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
    $Installer = "$env:TEMP\python-$PythonVersion-amd64.exe"

    if ((Get-Command python3 -ErrorAction SilentlyContinue) -and (& python3 --version).Contains($PythonVersion)) {
        Write-Host "Python $PythonVersion is already installed"
        return
    }

    Write-Host "Installing Python $PythonVersion..."
    Invoke-WebRequest -Uri $PythonUrl -OutFile $Installer
    Start-Process -FilePath $Installer -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait

    Write-Host "Python $PythonVersion installed"
    & python3 --version
    & pip3 --version
}

# Install dependencies
Install-BellSoftJDK8
Install-Ant
Install-Python38

# Install Python packages
& pip3 install numpy jinja2 --user

# Clone OpenCV repositories
Write-Host "Cloning OpenCV repositories..."
Set-Location -Path $BuildDir

if (-Not (Test-Path -Path "$BuildDir\opencv")) {
    git clone -b $OpenCVVersion --depth 1 https://github.com/opencv/opencv.git
}

if (-Not (Test-Path -Path "$BuildDir\opencv_contrib")) {
    git clone -b $OpenCVContribVersion --depth 1 https://github.com/opencv/opencv_contrib.git
}

# Configure and build OpenCV
Write-Host "Configuring and building OpenCV..."
$BuildOutputDir = "$BuildDir\build"
if (Test-Path -Path $BuildOutputDir) {
    Remove-Item -Recurse -Force -Path $BuildOutputDir
}
New-Item -ItemType Directory -Path $BuildOutputDir | Out-Null

cmake -G "Ninja" `
    -D CMAKE_BUILD_TYPE=Release `
    -D CMAKE_INSTALL_PREFIX=$InstallDir `
    -D OPENCV_EXTRA_MODULES_PATH="$BuildDir\opencv_contrib\modules" `
    -D BUILD_EXAMPLES=OFF `
    -D BUILD_TESTS=OFF `
    -D BUILD_PERF_TESTS=OFF `
    -D BUILD_SHARED_LIBS=OFF `
    -D OPENCV_ENABLE_NONFREE=ON `
    -D BUILD_LIST=core,imgproc,highgui,imgcodecs `
    -S "$BuildDir\opencv" `
    -B $BuildOutputDir

cmake --build $BuildOutputDir --parallel $NumJobs
cmake --install $BuildOutputDir --prefix $InstallDir

Write-Host "OpenCV build and installation complete!"