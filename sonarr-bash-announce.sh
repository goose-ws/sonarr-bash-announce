#!/usr/bin/env bash

###              DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
###                      Version 2, December 2004
###  
###   Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>
###  
###   Everyone is permitted to copy and distribute verbatim or modified
###   copies of this license document, and changing it is allowed as long
###   as the name is changed.
###  
###              DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
###     TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
###  
###    0. You just DO WHAT THE FUCK YOU WANT TO.
###  
###  ---
###  
###  Copyright © 2019 goose <goose@goose.ws>
###  This work is free. You can redistribute it and/or modify it under the
###  terms of the Do What The Fuck You Want To Public License, Version 2,
###  as published by Sam Hocevar. See http://www.wtfpl.net/ for more details.
###  This program is free software. It comes without any warranty, to
###  the extent permitted by applicable law. You can redistribute it
###  and/or modify it under the terms of the Do What The Fuck You Want
###  To Public License, Version 2, as published by Sam Hocevar. See
###  http://www.wtfpl.net/ for more details.

### About
# This script is meant to replace Sonarr's built in connection to Telegram,
# and be used for "Downloaded" and "Upgraded" options. It has not been made
# with the "Grab" or "Rename" options in mind, and may behave unpredictably
# if you enable it for those two options.
#
# The purpose of the script is to "pool" notifications for a series together,
# so that when grabbing an entire series, instead of getting hundreds of
# single notifications for single episodes, it pools them into a single
# notification for all the episodes combined.
#
# This script also doubles as an excuse for me to finally learn Python, which
# I will once day convert the source to. In the mean time... bash!

### Config
# The config file will be generated if it does not exist. Run the script in
# test mode (./sonarr-bash-announce.sh -t) to generate one.

### Begin source
# Define some variables
version="1.0.0"
pid="${$}"
dateEpoch="$(date +%s)"
dateFormatted="$(date)"
config="${0%.sh}"
config="${config##*/}"
config="${HOME}/.${config}-config"
sonarrUrl="${sonarrUrl%/}"
regex='http(s)?://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'

# Do a dependency check
fail="0"
req=("bash" "jq" "curl" "md5sum" "awk" "printf" "echo" "fold" "od" "tr")
for i in "${req[@]}"; do
	if ! which "${i}" >> /dev/null 2>&1; then
		echo "Missing dependency \"${i}\""
		fail="1"
	fi
done

# Check bash version
if [[ -z "${BASH_VERSINFO}" ]] || [[ -z "${BASH_VERSINFO[0]}" ]] || [[ ${BASH_VERSINFO[0]} -lt "4" ]]; then
	echo "This script requires Bash version >= 4"
	fail="1"
fi

# Check to see if config exists
if [[ -e "${config}" ]]; then
	# It does. Source it.
	source "${config}"
else
	# It does not.
	echo "Config does not exist. Generate one with the -g flag."
	fail="1"
fi
# Check to see if Sonarr URL is actually a URL
if ! [[ "${sonarrUrl}" =~ ${regex} ]]; then
	echo "Sonarr URL invalid"
	fail="1"
fi
# Check to see if our API key has been filled in
if [[ -z "${sonarrApi}" ]]; then
	echo "Sonarr API key blank"
	fail="1"
fi
# Check to see if our Telegram Bot ID has been filled in
if [[ -z "${telegramBotId}" ]]; then
	echo "Telegram Bot ID blank"
	fail="1"
fi
# Check to see if our Telegram Channel ID array has at least one item
if [[ "${#telegramChannelId[@]}" -eq "0" ]]; then
	echo "Telegram Channel ID blank"
	fail="1"
fi
# Check to see if ours notes directory has been filled in
if [[ -z "${notesDir}" ]]; then
	echo "Notes Directory config option (notesDir) is empty"
	fail="1"
else
	# Trim any trailing slashes
	notesDir="${notesDir%/}"
	# Check to make sure the directory exists
	if ! [[ -d "${notesDir}" ]]; then
		# It does not. Try to create it.
		mkdir -p "${notesDir}"
		if ! [[ -d "${notesDir}" ]]; then
			# We failed to create it.
			echo "Directory \"${notesDir}\" does not appear to exist, and cannot be created."
			fail=1
		fi
	fi
	# Try to write to the test directory
	if [[ -d "${notesDir}" ]] && ! touch "${notesDir}/${pid}" >> /dev/null 2>&1; then
		# We can't
		echo "Unable to write to \"${notesDir}\""
		fail=1
	else
		# We can
		rm "${notesDir}/${pid}"
	fi
fi
if [[ "${fail}" -eq "1" ]]; then
	# Quit if we failed
	exit 1
fi

# This will prevent the script from running more than one instance at a time,
# by forcing any instances with a PID higher than the lowest PID to wait in line.
# The line is sorted numerically, not first-come-first-serve. We'll re-check the
# lock file every second to see if it's our turn yet.
lockfile="${notesDir}/${0##*/}.lock"
debugArr+=("lock: ${lockfile}")
echo "${pid}" >> "${lockfile}"
sleep 1
turnToGo="$(sort -n "${lockfile}" | head -n 1)"
while [[ "${turnToGo}" -ne "${pid}" ]]; do
	sleep 1
	turnToGo="$(sort -n "${lockfile}" | head -n 1)"
done

## Define some functions
# Lockfile handler on exit
removeLock () {
# Could be done with tools, but let's do it with pure bash
readarray -t lineArr < "${lockfile}"
if [[ "${#lockfile[@]}" -gt "1" ]]; then
	while read i; do
		if ! [[ "${i}" -eq "${pid}" ]]; then
			echo "${i}" >> "${lockfile}.tmp"
		fi
	done < "${lockfile}"
	mv "${lockfile}.tmp" "${lockfile}"
else
	rm "${lockfile}"
fi
}

# "Debugger" tool
exitDebug() {
debugFile="${notesDir}/${dateEpoch}.${pid}"
echo "Date: ${dateFormatted}" >> "${debugFile}"
echo "Epoch: ${dateEpoch}" >> "${debugFile}"
echo "PID: ${pid}" >> "${debugFile}"
echo "pwd: $(pwd)" >> "${debugFile}"
echo "" >> "${debugFile}"
echo "=====" >> "${debugFile}"
echo "" >> "${debugFile}"
echo "Logic:" >> "${debugFile}"
for i in "${debugArr[@]}"; do
	echo "${i}" >> "${debugFile}"
done
echo ""
echo "=====" >> "${debugFile}"
echo "" >> "${debugFile}"
echo "printenv:" >> "${debugFile}"
printenv >> "${debugFile}"
echo "" >> "${debugFile}"
echo "=====" >> "${debugFile}"
echo "" >> "${debugFile}"
echo "Local variables:" >> "${debugFile}"
( set -o posix ; set ) >> "${debugFile}"
# Remove sensitive info from the debug file. We don't need it anyways.
redactedArr+=("$(sed -e 's/[\/&]/\\&/g' <<<"${sonarrUrl}")")
redactedArr+=("$(sed -e 's/[\/&]/\\&/g' <<<"${sonarrApi}")")
redactedArr+=("$(sed -e 's/[\/&]/\\&/g' <<<"${sedTelegramBotId}")")
for i in "${telegramChannelId[@]}"; do
	redactedArr+=("$(sed -e 's/[\/&]/\\&/g' <<<"${i}")")
done
for i in "${redactedArr[@]}"; do
	sed -i "s/${i}/[Redacted]/g" "${debugFile}"
done
removeLock;
exit 1
}

# Generate config file
genConfig () {
echo '# Sonarr base URL (Sonarr > Settings > General -- "Protocol (http[s]://)" + "Bind Address" + ":Port Number" + "/URL Base"' 
echo '# Example: sonarrUrl="http://127.0.0.1:8989/sonarr"' 
echo 'sonarrUrl=""' 
echo '' 
echo '# Sonarr API key (Sonarr > General > API Key)' 
echo 'sonarrApi=""' 
echo '' 
echo '# Telegram bot API key, obtained from @BotFather' 
echo 'telegramBotId=""' 
echo '' 
echo '# Telegram channel ID. For help obtaining this, see this link:' 
echo '# https://github.com/GabrielRF/telegram-id' 
echo '# This is an array, so you can add as many channels as you like.'
echo '# Example: telegramChannelId=("-1001234567890" "-1000987654321")'
echo 'telegramChannelId=("")' 
echo '' 
echo '# How many downloads of a series should be the cutoff to pool the notifications?' 
echo '# This is a 'greater than or equal to' number.' 
echo '# Default should be fine' 
echo 'concurrent="3"' 
echo '' 
echo '# Point me to a directory where I can leave notes for myself. While this may not' 
echo '# be the "ideal" way to do it, since the script is only going to run when it is' 
echo '# called by Sonarr and then exit, I need a place for past me to leaves notes for' 
echo '# previous me, on pooled notifications. In an ideal world, this might be handled' 
echo '# by a database or something. In the mean time, plain text files will do...' 
echo '# Default should be fine' 
echo 'notesDir="${HOME}/.sonarr"' 
}

# URL encoder. Done using bash, to prevent any additional dependencies.
# Handy little function I got from here: https://stackoverflow.com/a/38021063
# But also a prime example of why I should learn to do this in Python
urlencodepipe() {
  local LANG=C; local c; while IFS= read -r c; do
    case $c in [a-zA-Z0-9.~_-]) printf "$c"; continue ;; esac
    printf "$c" | od -An -tx1 | tr ' ' % | tr -d '\n'
  done <<EOF
$(fold -w1)
EOF
  echo
}
urlencode() { printf "$*" | urlencodepipe ;}

# Sort episodes into a range
# Handy little function I got from here: https://stackoverflow.com/a/13709154
sortEpisodes() {
# TODO: Figure out why I need to pad this array with a blank item at the end to make it work
epNumSortArr+=("")
for num in "${epNumSortArr[@]}"; do
	if [[ -z "${first}" ]]; then
		first="${num}"
		last="${num}"
		continue
	fi
	if [[ "${num}" -ne "$(( ${last} + 1))" ]]; then
		if [[ "${first}" -eq "${last}" ]]; then
			echo -n "${first},"
		else
			echo -n "${first}-${last},"
		fi
		first="${num}"
		last="${num}"
	else
		(( last++ ))
	fi
	(( n++ ))
done
unset epNumSortArr
unset first
unset last
}

# Test to make sure Telegram's API is:
# 1. Reachable
# 2. Authenticating
testTelegram () {
telegramOutput="$(curl -s "https://api.telegram.org/bot${telegramBotId}/getMe" 2>&1)"
curlExitCode="${?}"
if [[ "${curlExitCode}" -ne "0" ]]; then
	debugArr+=("[48] curlExitCode: ${curlExitCode}")
	echo "Curl returned a non-zero exit code. Considered failure."
	exitDebug;
elif [[ -z "${telegramOutput}" ]]; then
	debugArr+=("[49] curlExitCode: ${curlExitCode} | #telegramOutput: ${#telegramOutput} | telegramOutput: ${telegramOutput}")
	echo "Curl returned an empty string. Considered failure."
	exitDebug;
fi
telegramOutputOrig="${telegramOutput}"
telegramOutput="${telegramOutput#*:}"
telegramOutput="${telegramOutput%%,*}"
if [[ "${telegramOutput,,}" == "true" ]]; then
	debugArr+=("[50] telegramOutputOrig: ${telegramOutputOrig} | telegramOutput: ${telegramOutput}")
	curlExitCode="0"
elif [[ "${telegramOutput,,}" == "false" ]]; then
	debugArr+=("[51] telegramOutputOrig: ${telegramOutputOrig} | telegramOutput: ${telegramOutput}")
	echo "Telegram returned a failed API attempt. Check your config settings. Considered failure."
	exitDebug;
else
	debugArr+=("[52] telegramOutputOrig: ${telegramOutputOrig} | telegramOutput: ${telegramOutput}")
	echo "Unexpected response from Telegram API server. Check your config settings. Considered failure."
	exitDebug;
fi
}

# Send a single notification
sendSingleNotification() {
# Pad with zero
if [[ "${seriesSeason}" -lt "10" ]]; then
	seriesSeason="0${seriesSeason}"
fi
if [[ "${seriesEpNum}" -lt "10" ]]; then
	seriesEpNum="0${seriesEpNum}"
fi
# Encode our text. The '%0A' is read by Telegram as a line break, so we want
# that to go in between our lines, and not encode it.
encodedText="$(urlencode "<b>Episode Downloaded</b>")%0A$(urlencode "${seriesTitle} - S${seriesSeason}E${seriesEpNum} - \"${seriesEpisodeTitle}\" [${seriesQuality}]")"
# Make sure Telegram is online and reachable
testTelegram;
# Send the emssage to each of our channels
for telegramChan in "${telegramChannelId[@]}"; do
	telegramOutput="$(curl -s "https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}" 2>&1)"
	curlExitCode="${?}"
	if [[ "${curlExitCode}" -ne "0" ]]; then
		debugArr+=("[32] curl -s \"https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}\"")
		debugArr+=("[33] curlExitCode: ${curlExitCode}")
		exitDebug;
	fi
	telegramOutputOrig="${telegramOutput}"
	telegramOutput="${telegramOutput#*:}"
	telegramOutput="${telegramOutput%%,*}"
	if [[ "${telegramOutput,,}" == "false" ]]; then
		debugArr+=("[34] curl -s \"https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}\"")
		debugArr+=("[35] telegramOutputOrig: ${telegramOutputOrig}")
		exitDebug;
	fi
done
removeLock;
exitDebug; #exit 0
}

# Pool multiple notifications for sending
poolNotifications() {
n="0"
while read -r i; do
	if [[ "${n}" -eq "0" ]]; then
		sendArr0+=("${i}")
	elif [[ "${n}" -eq "1" ]]; then
		sendArr1+=("${i}")
	elif [[ "${n}" -eq "2" ]]; then
		sendArr2+=("${i}")
	elif [[ "${n}" -eq "3" ]]; then
		sendArr3+=("${i}")
	elif [[ "${n}" -eq "4" ]]; then
		sendArr4+=("${i}")
	fi
	debugArr+=("[10-${n}] sendArr${n}: ${i}")
	if [[ "${n}" -eq "4" ]]; then
		n="0"
	else
		(( n++ ))
	fi
done < "${output}"
n="0"
for i in "${sendArr1[@]}"; do
	echo "${sendArr2[${n}]}" >> "${output}-${i}"
	echo "${sendArr4[${n}]}" >> "${output}-${i}"
	debugArr+=("[11-${n}] sendArr2[n]: ${sendArr2[${n}]}")
	debugArr+=("[11-${n}] sendArr4[n]: ${sendArr4[${n}]}")
	(( n++ ))
done
readarray -t seasonsToProcess <<<"$(for i in "${sendArr1[@]}"; do echo "${i}"; done | sort -u)"
debugArr+=("[12] seasonsToProcess[@]: ${seasonsToProcess[@]}")
echo "${sendArr0[0]}" >> "${output}-buffer"
for i in "${seasonsToProcess[@]}"; do
	n=0
	debugArr+=("[13-${n}] i: ${i}")
	unset epNumSortArr
	unset qualSortArr
	unset seasonEpisodes
	unset seasonQuality
	while read z; do
		if [[ "${n}" -eq "0" ]]; then
			debugArr+=("[14] z: ${z}")
			epNumSortArr+=("${z}")
			(( n++ ))
		else
			debugArr+=("[15] z: ${z}")
			qualSortArr+=("${z}")
			n="0"
		fi
	done < "${output}-${i}"
	readarray -t epNumSortArr <<<"$(for i in "${epNumSortArr[@]}"; do echo -e "${i}"; done | sort -n)"
	seasonEpisodes="$(sortEpisodes)"
	seasonEpisodes="${seasonEpisodes%,}"
	readarray -t seasonQuality <<<"$(for i in "${qualSortArr[@]}"; do echo "${i}"; done | sort -u)"
	if [[ "${#seasonQuality}" -gt "1" ]]; then
		seasonQuality="$(for z in "${seasonQuality[@]}"; do echo -n "${z} & "; done)"
		seasonQuality="${seasonQuality% & }"
		debugArr+=("[16] seasonQuality: ${seasonQuality}")
	else
		seasonQuality="${seasonQuality[0]}"
		debugArr+=("[17] seasonQuality: ${seasonQuality}")
	fi
	echo "Season ${i} Episodes ${seasonEpisodes} [${seasonQuality}]" >> "${output}-buffer"
done
rm "${output}"
for i in "${sendArr1[@]}"; do
	rm "${output}-${i}"
done
}

# Everything is defined. Now let's do some stuff.
if [[ "${#sonarr_eventtype}" -eq "0" ]]; then
	# The script was started by a user, not by sonarr
	case "${1,,}" in
	-c)
		if [[ -e "${config}" ]]; then
			echo "Found old config at ${config} -- Moving to ${config}.old"
			mv "${config}" "${config}.old"
			echo ""
		fi
		if [[ -e "${config}" ]]; then
			echo "Unable to move old config."
			exit 1
		fi
		genConfig >> "${config}"
		echo "Config file created at: ${config}"
		echo "Please fill it out and then re-run the script."
		removeLock;
		exitDebug; #exit 0
		;;
	-h)
		echo "Usage:"
		echo "-c  Generate config file"
		echo "-h  Display this help message"
		echo "-t  Test connection to Telegram"
		echo "-u  Check for updates"
		echo "-v  Print version number"
		removeLock;
		exitDebug; #exit 0
		;;
	-t)
		encodedText="$(urlencode "<b>Subject</b>")%0A$(urlencode "This is a test.")"
		for telegramChan in "${telegramChannelId[@]}"; do
			curlReturn="$(curl -s "https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}" 2>&1)"
			if [[ "${?}" -ne "0" ]]; then
				echo "[Channel ID: ${telegramChan}] Curl returned a non-zero exit code. Considered failure."
			elif [[ -z "${curlReturn}" ]]; then
				echo "[Channel ID: ${telegramChan}] Curl returned an empty string. Considered failure."
			fi
			curlReturn="${curlReturn#*:}"
			curlReturn="${curlReturn%%,*}"
			if [[ "${curlReturn,,}" == "true" ]]; then
				echo "[Channel ID: ${telegramChan}] Test successful"
			elif [[ "${curlReturn,,}" == "false" ]]; then
				echo "[Channel ID: ${telegramChan}] Telegram returned a failed API attempt. Check your config settings. Considered failure."
			else
				echo "[Channel ID: ${telegramChan}] Unexpected response from Telegram API server. Check your config settings. Considered failure."
			fi
		done
		removeLock;
		exitDebug; #exit 0
		;;
	-u)
		echo "Checking for updates..."
		isNum='^[0-9]+$'
		githubSrc="$(curl -s "https://raw.githubusercontent.com/goose-ws/sonarr-bash-announce/master/sonarr-bash-announce.sh")"
		if [[ "${?}" -ne "0" ]]; then
			echo "Unable to reach GitHub"
			removeLock;
			exit 1
		fi
		newVer="$(grep -m 1 "version=" <<<"${githubSrc}")"
		newVer="${newVer#*\"}"
		newVer="${newVer%\"}"
		if [[ -z "${newVer}" ]]; then
			echo "Unable to retrieve current version number."
			removeLock;
			exit 1
		elif ! [[ "${newVer}" =~ ${re} ]]; then
			echo "Unable to parse current version number."
			removeLock;
			exit 1
		elif [[ "${newVer//./}" -gt "${version//./}" ]]; then
			echo "Newer version available."
			echo "Current version: ${version}"
			echo "New version: ${newVer}"
			echo""
			echo "Please pull newest version from git, and view github and the commit log for possible config changes"
			echo "https://github.com/goose-ws/sonarr-bash-announce"
		else
			echo "No updates available."
		fi
		removeLock;
		exitDebug; #exit 0
		;;
	-v)
		echo "Version ${version}"
		removeLock;
		exitDebug; #exit 0
		;;
	*)
		echo "Invalid option. Use flag -h for help."
		removeLock;
		exit 1
		;;
	esac
fi

# Define some new variables
seriesTitle="${sonarr_series_title}"
seriesSeason="${sonarr_episodefile_seasonnumber}"
seriesEpNum="${sonarr_episodefile_episodenumbers}"
seriesQuality="${sonarr_episodefile_quality}"
seriesEpisodeTitle="${sonarr_episodefile_episodetitles}"
outputFile="$(md5sum <<<"${seriesTitle}" | awk '{print $1}')"
output="${notesDir}/${outputFile}"
# Check to make sure we can reach Sonarr
debugArr+=("[0] curl -s \"${sonarrUrl}/api/queue?apikey=${sonarrApi}\"")
curlOut="$(curl -s "${sonarrUrl}/api/queue?apikey=${sonarrApi}" 2>&1)"
curlExitCode="${?}"
debugArr+=("[0] curlExitCode: ${curlExitCode}")
debugArr+=("[0] curlOut:")
debugArr+=("${curlOut}")
if [[ "${curlExitCode}" -ne "0" ]]; then
	echo "Curl returned non-zero exit code"
	exitDebug;
fi
# Run the response we got from curl through jq to get what we want
# Big thanks to SnoFox for helping me with this.
curlEncoded="$(echo "${curlOut}" | jq -r '.[] | "\(.series.title)\n\(.episode.seasonNumber)\n\(.episode.episodeNumber)\n\(.quality.quality.name)\n\(.episode.title)"')"
n="0"
debugArr+=("[1] curlEncoded: ${curlEncoded}")
while read -r i; do
	if [[ "${n}" -eq "0" ]]; then
		seriesArr+=("${i}")
	elif [[ "${n}" -eq "1" ]]; then
		seasonArr+=("${i}")
	elif [[ "${n}" -eq "2" ]]; then
		episodeArr+=("${i}")
	elif [[ "${n}" -eq "3" ]]; then
		qualityArr+=("${i}")
	elif [[ "${n}" -eq "4" ]]; then
		epNameArr+=("${i}")
	fi
	if [[ "${n}" -eq "4" ]]; then
		n="0"
	else
		(( n++ ))
	fi
done <<<"${curlEncoded}"
# Check our arrays to make sure they have an equal amount of items.
# Since we're iterating through each array individually, we need to make
# sure that we'll be working on the same item from each respective array
debugArr+=("[2] #seriesArr[@]: ${#seriesArr[@]} | #seasonArr[@]: ${#seasonArr[@]} | #episodeArr[@]: ${#episodeArr[@]} | #qualityArr[@]: ${#qualityArr[@]} | #epNameArr[@]: ${#epNameArr[@]}")
if [[ "${#seriesArr[@]}" -ne "${#seasonArr[@]}" ]] || [[ "${#seriesArr[@]}" -ne "${#episodeArr[@]}" ]] || [[ "${#seriesArr[@]}" -ne "${#qualityArr[@]}" ]] || [[ "${#seriesArr[@]}" -ne "${#epNameArr[@]}" ]]; then
	echo "Failure due to bad array from Sonarr"
	n="0"
	for i in "${seriesArr[@]}"; do
		debugArr+=("[2-${n}] seriesArr[${n}]: ${i}")
		(( n++ ))
	done
	n="0"
	for i in "${seasonArr[@]}"; do
		debugArr+=("[3-${n}] seasonArr[${n}]: ${i}")
		(( n++ ))
	done
	n="0"
	for i in "${episodeArr[@]}"; do
		debugArr+=("[4-${n}] episodeArr[${n}]: ${i}")
		(( n++ ))
	done
	n="0"
	for i in "${qualityArr[@]}"; do
		debugArr+=("[5-${n}] qualityArr[${n}]: ${i}")
		(( n++ ))
	done
	n="0"
	for i in "${epNameArr[@]}"; do
		debugArr+=("[6-${n}] epNameArr[${n}]: ${i}")
		(( n++ ))
	done
	exitDebug;
fi

debugArr+=("[7] #seriesArr[@]: ${#seriesArr[@]}")
# If there is only one (or zero) items in the queue
if [[ "${#seriesArr[@]}" -le "1" ]]; then
	# If an output file exists for the series passed by sonarr
	if [[ -e "${output}" ]]; then
		# Add this file to the output
		debugArr+=("[8] Output exists")
		echo "${seriesTitle}" >> "${output}"
		echo "${seriesSeason}" >> "${output}"
		echo "${seriesEpNum}" >> "${output}"
		echo "${seriesEpisodeTitle}" >> "${output}"
		echo "${seriesQuality}" >> "${output}"
		# Pool our notifications
		poolNotifications;
		# Encode the message to be sent
		encodedText="$(urlencode "<b>Multiple Episodes Downloaded</b>")%0A$(while read i; do urlencode "${i}"; echo -n "%0A"; done < "${output}-buffer")"
		encodedText="$(tr -d '\n' <<<"${encodedText}")"
		encodedText="${encodedText%\%0A}"
		# Check to make sure Telegram is online/reachable
		testTelegram;
		# Send our message(s)
		for telegramChan in "${telegramChannelId[@]}"; do
			telegramOutput="$(curl -s "https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}" 2>&1)"
			curlExitCode="${?}"
			# Check to make sure curl returned exit code 0
			if [[ "${curlExitCode}" -ne "0" ]]; then
				debugArr+=("[36] curl -s \"https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}\"")
				debugArr+=("[37] curlExitCode: ${curlExitCode}")
				rm "${output}-buffer"
				exitDebug;
			fi
			# Check to make sure Telegram returned that the message was sent properly
			telegramOutputOrig="${telegramOutput}"
			telegramOutput="${telegramOutput#*:}"
			telegramOutput="${telegramOutput%%,*}"
			if [[ "${telegramOutput,,}" == "false" ]]; then
				debugArr+=("[38] curl -s \"https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}\"")
				debugArr+=("[39] telegramOutputOrig: ${telegramOutputOrig}")
				rm "${output}-buffer"
				exitDebug;
			fi
		done
		rm "${output}-buffer"
		removeLock;
		exitDebug; #exit 0
	else
		# No pooled notifications for this series, so we can send a single notification
		debugArr+=("[9] Output does not exist")
		sendSingleNotification;
	fi
else
	# There are two or more items in the queue
	debugArr+=("[18]")
	match="0"
	numMatch="0"
	# Let's find out how many more of this item are in the queue
	for i in "${seriesArr[@]}"; do
		if [[ "${i}" == "${seriesTitle}" ]]; then
			debugArr+=("[19] i: ${i} | seriesTitle: ${seriesTitle} | numMatch: ${numMatch}")
			match="1"
			(( numMatch++ ))
		fi
	done
	# If there is at least one match
	if [[ "${match}" -eq "1" ]]; then
		debugArr+=("[20] match: ${match}")
		# If the number of matches is less than or equal to one
		if [[ "${numMatch}" -le "1" ]]; then
			debugArr+=("[21] numMatch: ${numMatch}")
			# And the output file exists
			if [[ -e "${output}" ]]; then
				debugArr+=("[22] output: ${output}")
				echo "${seriesTitle}" >> "${output}"
				echo "${seriesSeason}" >> "${output}"
				echo "${seriesEpNum}" >> "${output}"
				echo "${seriesEpisodeTitle}" >> "${output}"
				echo "${seriesQuality}" >> "${output}"
				poolNotifications;
				encodedText="$(urlencode "<b>Multiple Episodes Downloaded</b>")%0A$(while read i; do urlencode "${i}"; echo -n "%0A"; done < "${output}-buffer")"
				encodedText="$(tr -d '\n' <<<"${encodedText}")"
				encodedText="${encodedText%\%0A}"
				testTelegram;
				for telegramChan in "${telegramChannelId[@]}"; do
					telegramOutput="$(curl -s "https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}" 2>&1)"
					curlExitCode="${?}"
					if [[ "${curlExitCode}" -ne "0" ]]; then
						debugArr+=("[40] curl -s \"https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}\"")
						debugArr+=("[41] curlExitCode: ${curlExitCode}")
						rm "${output}-buffer"
						exitDebug;
					fi
					telegramOutputOrig="${telegramOutput}"
					telegramOutput="${telegramOutput#*:}"
					telegramOutput="${telegramOutput%%,*}"
					if [[ "${telegramOutput,,}" == "false" ]]; then
						debugArr+=("[42] curl -s \"https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}\"")
						debugArr+=("[43] telegramOutputOrig: ${telegramOutputOrig}")
						rm "${output}-buffer"
						exitDebug;
					fi
				done
				rm "${output}-buffer"
				removeLock;
				exitDebug; #exit 0
			else
				debugArr+=("[23]")
				sendSingleNotification;
			fi
		# If the number of matches is greater than one, and greater than or equal to our concurrent value
		elif [[ "${numMatch}" -gt "1" ]] && [[ "${numMatch}" -ge "${concurrent}" ]]; then
			debugArr+=("[24] numMatch: ${numMatch} | concurrent: ${concurrent}")
			echo "${seriesTitle}" >> "${output}"
			echo "${seriesSeason}" >> "${output}"
			echo "${seriesEpNum}" >> "${output}"
			echo "${seriesEpisodeTitle}" >> "${output}"
			echo "${seriesQuality}" >> "${output}"
		# If the number of matches is greater than one, and less than our concurrent value
		elif [[ "${numMatch}" -gt "1" ]] && [[ "${numMatch}" -lt "${concurrent}" ]]; then
			debugArr+=("[25] numMatch: ${numMatch} | concurrent: ${concurrent}")
			if [[ -e "${output}" ]]; then
				debugArr+=("[26] output: ${output}")
				echo "${seriesTitle}" >> "${output}"
				echo "${seriesSeason}" >> "${output}"
				echo "${seriesEpNum}" >> "${output}"
				echo "${seriesEpisodeTitle}" >> "${output}"
				echo "${seriesQuality}" >> "${output}"
			else
				debugArr+=("[27]")
				sendSingleNotification;
			fi
		fi
	# If there are no matches in the queue
	elif [[ "${match}" -eq "0" ]]; then
		debugArr+=("[28] match: ${match}")
		# If an output file exists for this series
		if [[ -e "${output}" ]]; then
			debugArr+=("[29] output: ${output}")
			echo "${seriesTitle}" >> "${output}"
			echo "${seriesSeason}" >> "${output}"
			echo "${seriesEpNum}" >> "${output}"
			echo "${seriesEpisodeTitle}" >> "${output}"
			echo "${seriesQuality}" >> "${output}"
			poolNotifications;
			encodedText="$(urlencode "<b>Multiple Episodes Downloaded</b>")%0A$(while read i; do urlencode "${i}"; echo -n "%0A"; done < "${output}-buffer")"
			encodedText="$(tr -d '\n' <<<"${encodedText}")"
			encodedText="${encodedText%\%0A}"
			testTelegram;
			for telegramChan in "${telegramChannelId[@]}"; do
				telegramOutput="$(curl -s "https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}" 2>&1)"
				curlExitCode="${?}"
				if [[ "${curlExitCode}" -ne "0" ]]; then
					debugArr+=("[44] curl -s \"https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}\"")
					debugArr+=("[45] curlExitCode: ${curlExitCode}")
					rm "${output}-buffer"
					exitDebug;
				fi
				telegramOutputOrig="${telegramOutput}"
				telegramOutput="${telegramOutput#*:}"
				telegramOutput="${telegramOutput%%,*}"
				if [[ "${telegramOutput,,}" == "false" ]]; then
					debugArr+=("[46] curl -s \"https://api.telegram.org/bot${telegramBotId}/sendMessage?chat_id=${telegramChan}&parse_mode=html&text=${encodedText}\"")
					debugArr+=("[47] telegramOutputOrig: ${telegramOutputOrig}")
					rm "${output}-buffer"
					exitDebug;
				fi
			done
			rm "${output}-buffer"
			removeLock;
			exitDebug; #exit 0
		else
			debugArr+=("[30]")
			sendSingleNotification;
		fi
	else
		debugArr+=("[31]")
		exitDebug;
	fi
fi
removeLock;
exitDebug; #exit 0
