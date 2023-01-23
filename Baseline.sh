#!/bin/zsh
#set -x
dryRun=1

#   Written by Trevor Sysock of Second Son Consulting
#   @BigMacAdmin on the MacAdmins Slack
#   trevor@secondsonconsulting.com

scriptVersion="v.0.5.0"

########################################################################################################
########################################################################################################
##
##      DEFINE INITIAL VARIABLES
##
########################################################################################################
########################################################################################################

if [ "${1}" = '--version' ]; then
    echo "$(basename $0) by Second Son Consulting - v. $scriptVersion"
    exit 0
fi

#######################
#   Customizations    #
#######################
#Variables for our primary Dialog window
dialogTitle="Your computer setup is underway"
dialogMessage="This can take a while. \n\nPlease sit back and wait while we make sure things get setup properly..."
dialogIcon="SF=laptopcomputer"
dialogOverlayIcon="/System/Library/CoreServices/Erase Assistant.app"
dialogAdditionalOptions=(
    --blurscreen
    --width 900
    --height 550
)

#Variables for our Successful Completion Dialog window
successDialogTitle="Your computer setup is complete"
successDialogMessage="Your device will automatically restart in 30 seconds."
successDialogIcon="$dialogIcon"
successDialogOverlayIcon="$dialogOverlayIcon"
successDialogAdditionalOptions=(
    --blurscreen
    --height 550
)
successDialogRestartButtonText="Restart Now"

#Variables for our Failure Completion Dialog window
failureDialogTitle="Your computer setup is complete"
failureDialogMessage="Your computer setup is complete, however not everything was installed as expected. Review the list below, and contact IT if you need assistance."
failureDialogIcon="$dialogIcon"
failureDialogOverlayIcon="$dialogOverlayIcon"
failureDialogAdditionalOptions=(
    --blurscreen
    --height 550
)
failureDialogRestartButtonText="Restart Now"

#Default Installomator Options
defaultInstallomatorOptions=(
    
)

if [ "$dryRun" = 1 ]; then
    defaultInstallomatorOptions+="DEBUG=2"
fi


#################################
#   Declare file/folder paths   #
#################################
#Baseline files/folders
BaselineConfig="/Library/Managed Preferences/com.secondsonconsulting.baseline.plist"
BaselineDir="/usr/local/Baseline"
logFile="/var/log/Baseline.log"
BaselinePath="$BaselineDir/Baseline.sh"
BaselineScripts="$BaselineDir/Scripts"
BaselinePackages="$BaselineDir/Packages"
BaselineLaunchDaemon="/Library/LaunchDaemons/com.secondsonconsulting.baseline.plist"

#Binaries
pBuddy="/usr/libexec/PlistBuddy"
dialogPath="/usr/local/bin/dialog"
dialogAppPath="/Library/Application Support/Dialog/Dialog.app"
installomatorPath="/usr/local/Installomator/Installomator.sh"

#Other stuff
dialogCommandFile=$(mktemp /var/tmp/baselineDialog.XXXXXX)

########################################################################################################
########################################################################################################
##
##      DEFINE FUNCTIONS
##
########################################################################################################
########################################################################################################

#################################
#   Logging and Housekeeping    #
#################################

function check_root()
{

# check we are running as root
if [[ $(id -u) -ne 0 ]]; then
  echo "ERROR: This script must be run as root **EXITING**"
  exit 1
fi
}

function make_directory()
{
    if [ ! -d "${1}" ]; then
        debug_message "Folder does not exist. Making it: ${1}"
        mkdir -p "${1}"
    fi
}

#Used only for debugging. Gives feedback into standard out if verboseMode=1, also to $logFile if you set it
function debug_message()
{
    if [ "$verboseMode" = 1 ]; then
    	/bin/echo "DEBUG: $*"
    fi
}

#Publish a message to the log (and also to the debug channel)
function log_message()
{
    if [ -e "$logFile" ]; then
    	/bin/echo "$(date): $*" >> "$logFile"
    fi

    if [ "$verboseMode" = 1 ]; then
    	debug_message "$*"
    fi
}

#Report messages go to our report, but also pass through log_message (and thus, also to debug_message)
function report_message()
{
    /bin/echo "$@" >> "$reportFile"
    log_message "$@"
}

# Initiate logging
function initiate_logging()
{
if ! touch "$logFile" ; then
    debug_message "ERROR: Logging fail. Cannot create log file"
    exit 1
else
    log_message "Baseline.sh initiated"
fi
}

#Only delete something if the variable has a value!
function rm_if_exists()
{
    if [ -n "${1}" ] && [ -e "${1}" ];then
        /bin/rm -rf "${1}"
    fi
}

function initiate_report()
{
    reportFile="/usr/local/Baseline/Baseline-Report.txt"
    if ! touch "$reportFile" ; then
        debug_message "ERROR: Reporting fail. Cannot create report file"
        exit 1
    else
        rm_if_exists "$reportFile"
        report_message "Report created: $(date)"
    fi
}

#Define our script exit process. Usage: cleanup_and_exit 'exitcode' 'exit message'
function cleanup_and_exit()
{
    log_message "Exiting: $2"
    while [ -e "$BaselineLaunchDaemon" ]; do
        rm_if_exists "$BaselineLaunchDaemon"
        sleep 1
    done
    kill "$caffeinatepid"
    dialog_command "quit:" 
    rm_if_exists "$dialogCommandFile"
    if [ "$dryRun" != 1 ]; then
        rm_if_exists "$BaselineDir"
    fi
    exit "$1"
}

function cleanup_and_restart()
{
    log_message "Exiting: $2"
    while [ -e "$BaselineLaunchDaemon" ]; do
        rm_if_exists "$BaselineLaunchDaemon"
        sleep 1
    done
    kill "$caffeinatepid"
    pkill caffeinate 
    dialog_command "quit:" 
    rm_if_exists "$dialogCommandFile"
    rm_if_exists "$scriptPath"
  
    # If this isn't a test run, force a restart
    if [ "$dryRun" != 1 ]; then
        shutdown -r now
    fi
    #Everything below here in this function is for testing/debugging
    echo "this is where <shutdown -r now> would go"
    exit "$1"
}

function no_sleeping()
{

    /usr/bin/caffeinate -d -i -m -u &
    caffeinatepid=$!

}

# execute a dialog command
function dialog_command(){
#    debug_message "DIALOGCMD: $@"
    /bin/echo "$@"  >> $dialogCommandFile
    sleep .1
}

# execute a dialog command
function dialog_list_command()
{
    #    debug_message "DIALOGCMD: $@"
    /bin/echo "$@"  >> $dialogCommandFile
    sleep .1
}

#This function is modified from the awesome one given to us via Adam Codega. Thanks Adam!
#https://github.com/acodega/dialog-scripts/blob/main/dialogCheckFunction.sh

function install_dialog()
{

    # Check for Dialog and install if not found. We'll try 10 times before exiting the script with a fail.
    dialogInstallAttempts=0
    while [ ! -e "$dialogAppPath" ] && [ "$dialogInstallAttempts" -lt 10 ]; do
        # If Installomator is already here, just use that
        if [ -e "$installomatorPath" ]; then
            "$installomatorPath" swiftdialog INSTALL=force BLOCKING_PROCESS_ACTION=ignore > /dev/null 2>&1
        else
            # Get the URL of the latest PKG From the Dialog GitHub repo
            # Expected Team ID of the downloaded PKG
            dialogURL=$(curl --silent --fail "https://api.github.com/repos/bartreardon/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
            expectedDialogTeamID="PWA5E9TQ59"
            log_message "Dialog not found. Installing."
            # Create temporary working directory
            workDirectory=$( /usr/bin/basename "$0" )
            tempDirectory=$( /usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX" )
            # Download the installer package
            /usr/bin/curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"
            # Verify the download
            teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')
            # Install the package if Team ID validates
            if [ "$expectedDialogTeamID" = "$teamID" ]; then
                /usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /
                dialogInstallExitCode=$?
            fi
            if [ ! -e "$dialogAppPath" ]; then
                log_message "Dialog installation failed."
                sleep 5
                dialogInstallAttempts=$((dialogInstallAttempts+1))
            fi
            # Remove the temporary working directory when done
            rm_if_exists "$tempDirectory"
        fi
    done
}

function install_installomator()
{

    # Check for Installomator and install if not found. We'll try 10 times before exiting the script with a fail.
    installomatorInstallAttempts=0
    while [ ! -e "$installomatorPath" ] && [ "$installomatorInstallAttempts" -lt 10 ]; do
        # Get the URL of the latest PKG From the Installomator GitHub repo
        # Expected Team ID of the downloaded PKG
        installomatorURL=$(curl --silent --fail "https://api.github.com/repos/Installomator/Installomator/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
        expectedTeamID="JME5BW3F3R"
        log_message "Installomator not found. Installing."
        # Create temporary working directory
        workDirectory=$( /usr/bin/basename "$0" )
        tempDirectory=$( /usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX" )
        # Download the installer package
        /usr/bin/curl --location --silent "$installomatorURL" -o "$tempDirectory/Installomator.pkg"
        # Verify the download
        teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Installomator.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')
        # Install the package if Team ID validates
        if [ "$expectedTeamID" = "$teamID" ]; then
            /usr/sbin/installer -pkg "$tempDirectory/Installomator.pkg" -target /
            installomatorInstallExitCode=$?
        fi
        if [ ! -e "$installomatorPath" ]; then
            log_message "Installomator installation failed."
            sleep 5
            installomatorInstallAttempts=$((installomatorInstallAttempts+1))
        fi
        # Remove the temporary working directory when done
        rm_if_exists "$tempDirectory"  
    done
}

#Checks if a user is logged in yet, and if not it waits and loops until we can confirm there is a real user
function wait_for_user()
{
    #Set our test to false
    verifiedUser="false"

    #Loop until user is found
    while [ "$verifiedUser" = "false" ]; do
        #Get currently logged in user
        currentUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
        #Verify the current user is not root, loginwindow, or _mbsetupuser
        if [ "$currentUser" = "root" ] \
            || [ "$currentUser" = "loginwindow" ] \
            || [ "$currentUser" = "_mbsetupuser" ] \
            || [ -z "$currentUser" ] 
        then
        #If we aren't verified yet, wait 1 second and try again
        sleep 1
        else
            #Logged in user found, but continue the loop until Dock and Finder processes are running
            if pgrep -q "dock" && pgrep -q "Finder"; then
                uid=$(id -u "$currentUser")
                log_message "Verified User is logged in: $currentUser UID: $uid"
                verifiedUser="true"
            fi
        fi
    done
}

#Verify configuration file
function verify_configuration_file()
{
    #We need to make sure our configuration file is in place. By the time the user logs in, this should have happened.
    debug_message "Verifying configuration file. Failure here probably means an MDM profile hasn't been properly scoped, or there's a problem with the MDM delivering the profile."
    configFileTimeout=600
    configFileWaiting=0
    while [ ! -e $BaselineConfig ]; do
        #wait 2 seconds
        sleep 2
        debug_message "Configuration file not found"
        configFileWaiting=$((configFileWaiting+2))
        if [ $configFileWaiting -gt $configFileTimeout ]; then
            cleanup_and_exit 1 "ERROR: Configuration file not found within $configFileTimeout seconds. Exiting."
        fi
    done
    debug_message "Configuration file found successfully."

}

function build_installomator_array()
{
    #Set an index internal to this function
    index=0
    #Loop through and test if there is a value in the slot of this index for the given array
    #If this command fails it means we've reached the end of the array in the config file and we exit our loop

    while $pBuddy -c "Print :Installomator:${index}" "$BaselineConfig" > /dev/null 2>&1; do
        #Get the Display Name of the current item
        currentDisplayName=$($pBuddy -c "Print :Installomator:${index}:DisplayName" "$BaselineConfig")
        dialogList+="$currentDisplayName"
        #Done looping. Increase our array value and loop again.
        index=$((index+1))
    done
}

function process_installomator_labels()
{
    #Set an index internal to this function
    currentIndex=0
    #Loop through and test if there is a value in the slot of this index for the given array
    #If this command fails it means we've reached the end of the array in the config file (or there are none) and we exit our loop
    while $pBuddy -c "Print :Installomator:${currentIndex}" "$BaselineConfig" > /dev/null 2>&1; do
        if [ ! -e "$installomatorPath" ]; then
            cleanup_and_exit 1 "ERROR: Installomator failed to install after numerous attempts. Exiting."
        fi
        #Set the current label name
        currentLabel=$($pBuddy -c "Print :Installomator:${currentIndex}:Label" "$BaselineConfig")
        #Check if there are Options defined, and set the variable accordingly
        if $pBuddy -c "Print :Installomator:${currentIndex}:Options" "$BaselineConfig" > /dev/null 2>&1; then
            #This label has options defined
            currentOptions=$($pBuddy -c "Print :Installomator:${currentIndex}:Options" "$BaselineConfig")
        else
            #This label does not have options defined
            currentOptions=""
        fi
        #Get the display name of the label we're installing. We need this to update the dialog list
        currentDisplayName=$($pBuddy -c "Print :Installomator:${currentIndex}:DisplayName" "$BaselineConfig")
        #Update the dialog window so that this item shows as "pending"
        dialog_list_command "listitem: $currentDisplayName: wait"
        #Call installomator with our desired options. Default options first, so that they can be overriden by "currentOptions"
        $installomatorPath $currentLabel ${defaultInstallomatorOptions[@]} $currentOptions > /dev/null 2>&1
        installomatorExitCode=$?
        if [ $installomatorExitCode != 0 ]; then
            report_message "Installomator failed to install: $currentLabel - Exit Code: $installomatorExitCode"
            dialog_list_command "listitem: $currentDisplayName: fail"
            failList+=("$currentDisplayName")
        else
            report_message "Installomator successfully installed: $currentLabel"
            dialog_list_command "listitem: $currentDisplayName: success"
            successList+=("$currentDisplayName")
       fi
        currentIndex=$((currentIndex+1))
    done
}

function build_script_arrays()
{
    #Set an index internal to this function
    index=0
    #Loop through and test if there is a value in the slot of this index for the given array
    #If this command fails it means we've reached the end of the array in the config file and we exit our loop

    while $pBuddy -c "Print :Scripts:${index}" "$BaselineConfig" > /dev/null 2>&1; do
        #Get the Display Name of the current item
        currentDisplayName=$($pBuddy -c "Print :Scripts:${index}:DisplayName" "$BaselineConfig")
        dialogList+="$currentDisplayName"
        #Done looping. Increase our array value and loop again.
        index=$((index+1))
    done
}

function process_scripts()
{
    #Set an index internal to this function
    currentIndex=0
    #Loop through and test if there is a value in the slot of this index for the given array
    #If this command fails it means we've reached the end of the array in the config file (or there are none) and we exit our loop
    while $pBuddy -c "Print :Scripts:${currentIndex}" "$BaselineConfig" > /dev/null 2>&1; do
        #Get the display name of the label we're installing. We need this to update the dialog list
        currentDisplayName=$($pBuddy -c "Print :Scripts:${currentIndex}:DisplayName" "$BaselineConfig")
        #Set the current script name
        currentScriptPath=$($pBuddy -c "Print :Scripts:${currentIndex}:ScriptPath" "$BaselineConfig")
        #Check if the defined script is a remote path
        if [[ ${currentScriptPath:0:4} == "http" ]]; then
            #Set variable to the base file name to be downloaded
            currentScript="$BaselineScripts/"$(basename "$currentScriptPath")
            #Download the remote script, and put it in the Baseline Scripts directory
            curl -s --fail-with-body "${currentScriptPath}" -o "$currentScript"
            #Capture the exit code of our curl command
            scriptDownloadExitCode=$?
            #Check if curl exited cleanly
            if [ "$scriptDownloadExitCode" != 0 ];then
                #Report a failed download
                report_message "ERROR: Script failed to download. Check your URL: $currentScriptPath"
                #Rm the output of our curl command. This will result in it being processed as a failure
                rm_if_exists "$currentScript"
            else
                report_message "Script downloaded successfully: $currentScriptPath"
                #Make our downloaded script executable
                chmod +x "$currentScript"
            fi
        #Check if the given script exists on disk
        elif [ -e "$currentScriptPath" ]; then
            # The path to the script is a local file path which exists
            currentScript="$currentScriptPath"
        elif [ -e "$BaselineScripts/$currentScriptPath" ]; then
            currentScript="$BaselineScripts/$currentScriptPath"
        fi
        #If the currentScript variable still isn't set to an existing file we need to bail..
        if [ ! -e "$currentScript" ]; then
            report_message "ERROR: Script does not exist: $currentScript"
            # Iterate the index up one
            currentIndex=$((currentIndex+1))
            # Report the fail
            dialog_list_command "listitem: $currentDisplayName: fail"
            failList+=("$currentDisplayName")
            # Bail this pass through the while loop and continue processing next item
            continue
        fi
        #Check for MD5 validation
        if $pBuddy -c "Print :Scripts:${currentIndex}:MD5" "$BaselineConfig" > /dev/null 2>&1; then
            #This script has MD5 validation provided
            #Read the expected MD5 value from the profile
            expectedMD5=$($pBuddy -c "Print :Scripts:${currentIndex}:MD5" "$BaselineConfig")
            #Calculate the actual MD5 of the script
            actualMD5=$(md5 -q "$currentScript")
            #Evaluate whether the expected and actual MD5 do not match
            if [ "$actualMD5" != "$expectedMD5" ]; then
                report_message "ERROR: MD5 value mismatch. Expected: $expectedMD5 Actual: $actualMD5"
                # Iterate the index up one
                currentIndex=$((currentIndex+1))
                # Report the fail
                dialog_list_command "listitem: $currentDisplayName: fail"
                failList+=("$currentDisplayName")
                # Bail this pass through the while loop and continue processing next item
                continue
            fi
        fi
        #Check if there are Arguments defined, and set the variable accordingly
        if $pBuddy -c "Print :Scripts:${currentIndex}:Arguments" "$BaselineConfig" > /dev/null 2>&1; then
            #This script has arguments defined
            currentArguments=$($pBuddy -c "Print :Scripts:${currentIndex}:Arguments" "$BaselineConfig")
        else
            #This script does not have arguments defined
            currentArguments=""
        fi
        #Now we have to do a trick in case there are multiple arguments, some of which are quoted together
        #Consider: /path/to/script.sh --font "Times New Roman"
        #Used the eval trick outlined here: https://superuser.com/questions/1066455/how-to-split-a-string-with-quotes-like-command-arguments-in-bash
        currentArgumentArray=()
        if [ -n "$currentArguments" ]; then
            eval 'for argument in '$currentArguments'; do currentArgumentArray+=$argument; done'
        fi

        #Update the dialog window so that this item shows as "pending"
        dialog_list_command "listitem: $currentDisplayName: wait"
        #Call our script with our desired options. Default options first, so that they can be overriden by "currentArguments"
        "$currentScript" ${currentArgumentArray[@]} > /dev/null 2>&1
        scriptExitCode=$?
        if [ $scriptExitCode != 0 ]; then
            report_message "Script failed to complete: $currentScript - Exit Code: $scriptExitCode"
            dialog_list_command "listitem: $currentDisplayName: fail"
            failList+=("$currentDisplayName")
        else
            report_message "Script completed successfully: $currentScript"
            dialog_list_command "listitem: $currentDisplayName: success"
            successList+=("$currentDisplayName")
       fi

       #Unset variables for next loop
       unset expectedMD5
       unset actualMD5
       unset currentArguments
       unset currentArgumentArray


       #Iterate index for next loop
        currentIndex=$((currentIndex+1))
    done
}

function build_pkg_arrays()
{
    #Set an index internal to this function
    index=0
    #Loop through and test if there is a value in the slot of this index for the given array
    #If this command fails it means we've reached the end of the array in the config file and we exit our loop

    while $pBuddy -c "Print :Packages:${index}" "$BaselineConfig" > /dev/null 2>&1; do
        #Get the Display Name of the current item
        currentDisplayName=$($pBuddy -c "Print :Packages:${index}:DisplayName" "$BaselineConfig")
        dialogList+="$currentDisplayName"
        #Done looping. Increase our array value and loop again.
        index=$((index+1))
    done
}

function process_pkgs()
{
    #Set an index internal to this function
    currentIndex=0
    #Loop through and test if there is a value in the slot of this index for the given array
    #If this command fails it means we've reached the end of the array in the config file (or there are none) and we exit our loop
    while $pBuddy -c "Print :Packages:${currentIndex}" "$BaselineConfig" > /dev/null 2>&1; do
        #Get the display name of the label we're installing. We need this to update the dialog list
        currentDisplayName=$($pBuddy -c "Print :Packages:${currentIndex}:DisplayName" "$BaselineConfig")
        #Set the current package path
        currentPKGPath=$($pBuddy -c "Print :Packages:${currentIndex}:PackagePath" "$BaselineConfig")
        
        ##Here is where we begin checking what kind of PKG was defined, and how to process it
        ##The end result of this chunk of code, is that we have a valid path to a PKG on the file system
        ##Else we bail and continue looping to install the next item

        #Check if the package path is a web URL
        if [[ ${currentPKGPath:0:4} == "http" ]]; then
            # The path to the PKG appears to be a URL.
            #^^^ CHANGE STUFF HERE ^^^#
            #Get the basename of the .pkg we're downloading
            pkgBasename=$(basename "$currentPKGPath")
            #Set the "currentPKG" variable, this gets used as the download path as well as processed later
            currentPKG="$BaselinePackages"/"$pkgBasename"
            #Check for conflict. If there's already a PKG in the directory we're downloading to, delete it
            rm_if_exists "$currentPKG"
            #Perform the download of the remote pkg
            curl -LJs "$currentPKGPath" -o "$currentPKG"
            #Capture the output of our curl command
            downloadResult=$?
            #Verify curl exited with 0
            if [ "$downloadResult" != 0 ]; then
                report_message "ERROR: PKG failed to download: $currentPKGPath"
                # Iterate the index up one
                currentIndex=$((currentIndex+1))
                # Report the fail
                dialog_list_command "listitem: $currentDisplayName: fail"
                # Bail this pass through the while loop and continue processing next item
                continue
            else
                debug_message "PKG downloaded successfully: $currentPKGPath downloaded to $currentPKG"
            fi
        fi
        
        # Check if the pkg exists
        if [ -e "$currentPKG" ]; then
            debug_message "PKG found: $currentPKG"
        elif [ -e "$currentPKGPath" ]; then
            # The path to the PKG appears to exist on the local file system
            currentPKG="$currentPKGPath"
        elif [ -e "$BaselinePackages/$currentPKGPath" ]; then
            # The path to the PKG appears to exist within Baseline directory
            currentPKG="$BaselinePackages/$currentPKGPath"
        else
            report_message "Package not found $currentPKGPath"
            dialog_list_command "listitem: $currentDisplayName: fail"
            failList+=("$currentDisplayName")
            currentIndex=$((currentIndex+1))
            continue
        fi

        ##At this point, the pkg exists on the file system, or we've bailed on this loop.

        #Check if there are Arguments defined, and set the variable accordingly
        if $pBuddy -c "Print :Packages:${currentIndex}:Arguments" "$BaselineConfig" > /dev/null 2>&1; then 
            #This pkg has arguments defined
            currentArguments=$($pBuddy -c "Print :Packages:${currentIndex}:Arguments" "$BaselineConfig")
        else
            #This pkg does not have arguments defined
            currentArguments=""
        fi
        #Now we have to do a trick in case there are multiple arguments, some of which are quoted together
        #Consider: /path/to/script.sh --font "Times New Roman"
        #Used the eval trick outlined here: https://superuser.com/questions/1066455/how-to-split-a-string-with-quotes-like-command-arguments-in-bash
        currentArgumentArray=()
        eval 'for argument in '$currentArguments'; do currentArgumentArray+=$argument; done'

        if $pBuddy -c "Print :Packages:${currentIndex}:TeamID" "$BaselineConfig" > /dev/null 2>&1; then
            #This pkg has TeamID defined
            currentTeamIDValidation=$($pBuddy -c "Print :Packages:${currentIndex}:TeamID" "$BaselineConfig")
        else
            #This pkg does not have TeamID Validation defined
            currentTeamIDValidation=""
        fi
        if $pBuddy -c "Print :Packages:${currentIndex}:MD5" "$BaselineConfig" > /dev/null 2>&1; then
            #This script has MD5 defined
            currentMD5Validation=$($pBuddy -c "Print :Packages:${currentIndex}:MD5" "$BaselineConfig")
        else
            #This script does not have MD5 defined
            currentMD5Validation=""
        fi
        #Update the dialog window so that this item shows as "pending"
        dialog_list_command "listitem: $currentDisplayName: wait"
        
        ## Package validation happens here
        # Check TeamID, if a value has been provided
        if [ -n "$currentTeamIDValidation" ]; then
            #Get the TeamID for the current PKG
            actualTeamID=$(spctl -a -vv -t install "$currentPKG" 2>&1 | awk -F '(' '/origin=/ {print $2 }' | tr -d ')' )
            # Check if actual does not match expected
            if [ "$currentTeamIDValidation" != "$actualTeamID" ]; then
                report_message "TeamID validation of PKG failed: $currentPKG - Expected: $currentTeamIDValidation Actual: $actualTeamID"
                dialog_list_command "listitem: $currentDisplayName: fail"
                failList+=("$currentDisplayName")
                # Iterate the index up one
                currentIndex=$((currentIndex+1))
                # Report the fail
                dialog_list_command "listitem: $currentDisplayName: fail"
                # Bail this pass through the while loop and continue processing next item
                continue
            else
                report_message "TeamID of PKG validated: $currentPKG $currentTeamIDValidation"
            fi
        fi
        
        # Check MD5, if a value has been provided
        if [ -n "$currentMD5Validation" ]; then
            #Get MD5 for the current PKG
            actualMD5=$(md5 -q "$currentPKG")
            # Check if actual does not match expected
            if [ "$currentMD5Validation" != "$actualMD5" ]; then
                report_message "MD5 validation of PKG failed: $currentPKG - Expected: $currentMD5Validation Actual: $actualMD5"
                dialog_list_command "listitem: $currentDisplayName: fail"
                failList+=("$currentDisplayName")
                # Iterate the index up one
                currentIndex=$((currentIndex+1))
                # Report the fail
                dialog_list_command "listitem: $currentDisplayName: fail"
                # Bail this pass through the while loop and continue processing next item
                continue
            else
                report_message "MD5 of PKG validated: $currentPKG $currentMD5Validation"
            fi
        fi

        ## The package installation happens here. We do this in a variable so we can capture the output and report it for debugging
	    pkgInstallerOutput=$(installer -allowUntrusted -pkg "$currentPKG" -target / ${currentArgumentArray[@]} )
        # Capture the installer exit code
        pkgExitCode=$?
        # Verify the install completed successfully
        if [ $pkgExitCode != 0 ]; then
            report_message "Package failed to complete: $currentPKG - Exit Code: $pkgExitCode"
            dialog_list_command "listitem: $currentDisplayName: fail"
            failList+=("$currentDisplayName")
        else
            report_message "Package completed successfully: $currentPKG"
            dialog_list_command "listitem: $currentDisplayName: success"
            successList+=("$currentDisplayName")
        fi
        debug_message "Output of the install package command: $pkgInstallerOutput"
        # Unset variables for next loop
        unset currentPKG
        unset currentPKGPath
        unset currentTeamIDValidation
        unset currentMD5Validation
        unset actualTeamID
        unset actualMD5
        unset currentArguments
        unset currentArgumentArray
        # Iterate to the next index item, and continue our loop
        currentIndex=$((currentIndex+1))
    done
}

function build_dialog_list_options()
{
    for i in $dialogList; do
        dialogListOptions+=(--listitem $i)
    done
}


#################################
#   Setup our timeout deadline  #
#################################

#How long do you want this script to run before admitting something went wrong and bailing out?
#Check if there's a custom timeout devined in the mobileconfig, and set it
if $pBuddy -c "Print :Timeout" "$BaselineConfig" > /dev/null 2>&1; then
    maximumDuration=$($pBuddy -c "Print :Timeout" "$BaselineConfig")
else
    #Else, set our default of 1 hour
    maximumDuration=3600
fi
current_epoch_time=$(date +%s)
timeout=$((maximumDuration+current_epoch_time))
bailOut=""
function timeout_check()
{
    if [ "$(date +%s)" -gt "$timeout" ] ; then
        bailOut=1
    fi
}

########################################################################################################
########################################################################################################
##
##      SCRIPT STARTS HERE
##
########################################################################################################
########################################################################################################
debug_message "Starting script actions"

#Verify we're running as root
check_root

#No falling asleep on the job, bud
no_sleeping

#Set trap so that things always exit cleanly
trap cleanup_and_exit 1 2 3 6

#Check if directories for Packages and Scripts exist already.
#This is useful for testing, or if running the script directly (not the pkg)
make_directory "$BaselineScripts"
make_directory "$BaselinePackages"

#Initiate Logging
initiate_logging

#Setup report
initiate_report

#############################################
#   Verify a Configuration File is in Place #
#############################################
verify_configuration_file

###########################
#   Install Installomator #
###########################
#If Installomator is going to be used, install it now
if $pBuddy -c "Print :Installomator:0" "$BaselineConfig" > /dev/null 2>&1; then
    install_installomator
fi

#########################
#   Install SwiftDialog #
#########################
install_dialog
#If swiftDialog still isn't installed, exit with an error
if [ ! -e "$dialogAppPath" ]; then
    cleanup_and_exit 1 "ERROR: SwiftDialog failed to install after numerous attempts. Exiting."
fi

#############################################
#   Wait until a user is verified logged in #
#############################################
wait_for_user

# Get the currently logged in user home folder and UID
currentUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
currentUserUID=$(/usr/bin/id -u "$currentUser")
userHomeFolder=$(dscl . -read /users/${currentUser} NFSHomeDirectory | cut -d " " -f 2)

#############
#   Arrays  #
#############

# Initiate arrays
dialogList=()
dialogListOptions=()
failList=()
successList=()

installomatorLabels=()
installomatorOptions=()

scriptsToProcess=()
scriptArguments=()

pkgsToInstall=()
pkgValidations=()

# Build dialogList array by reading our configuration and looping through things
build_installomator_array

build_pkg_arrays

build_script_arrays


##################################
#   Draw our dialog list window  #
##################################
build_dialog_list_options

#Create our initial Dialog Window
$dialogPath \
--title "$dialogTitle" \
--message "$dialogMessage" \
--icon "$dialogIcon" \
--overlayicon "$dialogOverlayIcon" \
${dialogAdditionalOptions[@]} \
--button1disabled \
--commandfile "$dialogCommandFile" \
--quitkey "]" \
${dialogListOptions[@]} \
& sleep 1

#########################
#   Install the things  #
#########################
process_installomator_labels

process_pkgs

process_scripts

#Check if we have a custom Dialog.app icon waiting to process. If yes, reinstall dialog
if [ -e "/Library/Application Support/Dialog/Dialog.png" ]; then
    dialog_list_command "listitem: add, title: Finishing up"
    dialog_list_command "listitem: Finishing up: wait"
    rm_if_exists "$dialogAppPath"
    install_dialog
    dialog_list_command "listitem: Finishing up: success"
fi

if [ "$dryRun" = 1 ]; then
    sleep 5
fi

#Close our running dialog window
dialog_command "quit:"



#Do final script swiftDialog stuff
#If the failList is empty, this means success
if [ -z "$failList" ]; then
    #Create our "Success" Dialog Window
    $dialogPath \
    --title "$successDialogTitle" \
    --message "$successDialogMessage" \
    --icon "$successDialogIcon" \
    --overlayicon "$successDialogOverlayIcon" \
    --button1text "$successDialogRestartButtonText" \
    ${successDialogAdditionalOptions[@]} \
    --timer 30
    cleanup_and_restart
else
    #Build fail list
    failListItems=()
    for i in ${failList[@]}; do
        failListItems+=(--listitem $i)
    done
    #Create our "Failure" Dialog Window
    $dialogPath \
    --title "$failureDialogTitle" \
    --message "$failureDialogMessage" \
    --icon "$failureDialogIcon" \
    --overlayicon "$failureDialogOverlayIcon" \
    --button1text "$failureDialogRestartButtonText" \
    ${failureDialogAdditionalOptions[@]} \
    ${failListItems[@]} \
    --timer 300

    cleanup_and_restart
fi
