#############################################################################################
# Script : ROBOCOPY.ps1																		#
# Version : 1.1																		     	#
# Last Updated : 2019-08-06																    #
# Maintainer : Samuel Ross (samuel.ross@cgi.com)											#
# Description : Kills open citrix connections, closes all open SMB files, 				   	#
# copies folder 1 to folder 2 using robocopy, adds user to AD group and renames old folder 	#
#############################################################################################



##############################################################################################################################
													### Script Parameters ###

# Set this parameter to true if you want to use a list like the other script, else set to false to run on whole directory
$USING_LIST = "true"		# Possible parameters : true false

# If USING_LIST to true, set CSV path here
$csv_path = "D:\Tools\Scripts\list.csv"       					# Example : "C:\Users\AL0539410\Desktop\list.csv"

# Set your AD Group to add and paths for the homes here
$add_group = "AG-FRHDTAR-FolderRedirection-HOMES"           	# Example : AD_GROUP_NAME
$old_home_path = "\\frhdtarsdp-df01\Home"   					# Example : C:\Home\Path
$new_home_path = "\\frhdtarsdp-df03\Homes"    					# Example : C:\Home\Path2
$log_path = "D:\Tools\Scripts\logs"


##############################################################################################################################

Add-PSSnapin citrix*

# Get all the folders in the home directory
$folders = Get-Item  $old_home_path\* ;
$log_full_path = "${log_path}\$(Get-Date -UFormat "%y-%m-%d_%R" | ForEach-Object { $_ -replace ":","." })-robocopy.txt"
$error_log = "$log_path\$(Get-Date -UFormat "%y-%m-%d_%R" | ForEach-Object { $_ -replace ":","." })-robocopy-errors.txt"

#If using a list, import it
if ($USING_LIST -eq "true"){$csv = Import-Csv -Path $csv_path}

#Run this loop for every folder found
Foreach ($usr in $folders)
{
	if($usr.Name -notlike "*move*")
    {

        #Initialize variables for this iteration of the loop
	    $username = $usr.Name #Sets the username in var (ex.: AL052891)
	    $source = $usr.FullName #Sets the source home full path in var (ex.: "F:\Data\Home\AL052891")
	    $destination = "$new_home_path\$username" #Sets the desto full path in var (ex.: "I:\Newpath\AL052891")
	
	    #If using list, validate if the user found is in the list
	    if ($USING_LIST -eq "true")
	    {
		    ForEach ($account In $csv)
		    {
			    if ($username -eq $account.Account)
			    {
                    write-host "Folder found for account $account! Copying $source"				

				    # Kill citrix sessions

                    if($(Get-BrokerSession  -AdminAddress "frhdtarclp-dc04.main.glb.corp.local:80" -Filter "((UserName -like `"*${username}*`") -and (SessionState -eq `"Active`"))"))
                    {
                        $i=0
				        Get-BrokerSession  -AdminAddress "frhdtarclp-dc04.main.glb.corp.local:80" -Filter "((UserName -like `"*${username}*`") -and (SessionState -eq `"Active`"))" | Stop-BrokerSession
				        Do 
						{
							Start-Sleep -s 1
							++$i
							write-host "Waiting for citrix session for $username to end for $i seconds!"
							if($i -ge 30)
							{
								write-host "Exceeded waiting time for $username !"
								echo "$username was not completed due to citrix timeout" | Out-File -FilePath "$error_log" -Append
								break
							}
                        }
                        While($(Get-BrokerSession  -AdminAddress "frhdtarclp-dc04.main.glb.corp.local:80" -Filter "((UserName -like `"*${username}*`") -and (SessionState -eq `"Active`"))"))
                    }
                
				    # Close open SMB files
				    Close-SmbOpenFile -ClientUserName "main\$username" -CimSession "FRHDTARSDP-DF01" -Force 
				
				    # Copy source to desto
                    echo "Copying $source" | Out-File -FilePath "$log_full_path" -Append
				    robocopy $source $destination /r:5 /w:2 /e /copyall /NFL /NDL /NJH /NS /NC /NP | Out-File -FilePath "$log_full_path" -Append
				
				    # Add user to AD group
				    Add-ADGroupMember -Identity $add_group -Members $username
				
				    # Rename old folder 
				    Rename-Item -Path $source -NewName "$old_home_path\${username}_move"
					
					echo "$username" | Out-File -FilePath "$log_path\lastuser.txt"
					Do 
					{
						write-host "Waiting for $log_path\lastuser.txt to be deleted"
						Start-Sleep -s 1
					}
					While(Test-Path "$log_path\lastuser.txt")
				
			    }	
		    }
	    }
	    else
	    {
	   
            if(! $source -like "*move*")
            {
                write-host "Copying folder : $source"
		        #If list is not being used, run loop for every folder found 
		
		        # Kill citrix sessions
		        Get-BrokerSession  -AdminAddress "frhdtarclp-dc04.main.glb.corp.local:80" -Filter "((UserName -like `"*${username}*`") -and (SessionState -eq `"Active`"))" | Stop-BrokerSession
			
		        # Close open SMB files
		        Close-SmbOpenFile -ClientUserName $username -CimSession "FRHDTARSDP-DF01" -Force
			
		        # Copy source to desto
		        robocopy $source $destination /r:5 /w:2 /e /copyall /NFL /NDL /NJH /NS /NC /NP | Out-File -FilePath "$log_full_path" -Append
		
		        # Add user to AD group
		        Add-ADGroupMember -Identity $add_group -Members $username
		
		        # Rename old folder 
		        Rename-Item -Path $source -NewName "$old_home_path\${username}_move"
            }
	    }
}
}





