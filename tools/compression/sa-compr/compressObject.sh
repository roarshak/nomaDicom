#!/bin/sh
#
# Component: util
#
# Description:
#  Compresses a DICOM object.
#
# Usage:
#   compressObject.sh -i <input-object> [ -o <output-object> ] [ -v ]
#
#    -i input-object  :  DICOM object filename to be compressed
#    -o output-object :  filename for the compressed file (equals to input-object if not specified)
#    -v		      :  verbose operation.
#    -t tabulation    :  prefix to be used for writing strings out.
#
# Last Updated     : $Author$
# Update Date Time : $Date$
# RCS File Name    : $RCSfile$
# RCS Revision     : $Revision$
# Locked by        : $Locker$
# Symbolic name    : $Name$
# State            : $State$
#

#When shopt -po xtrace returns 0 (success) it means set -x is enabled
if shopt -po xtrace >/dev/null; then
  set +x
  . $HOME/etc/setenv.sh
  set -x
else
  . $HOME/etc/setenv.sh
fi

# CompressionMode="None"
# MinLossyRatio="2.5"
# MinLosslessRatio="1.5"

# NOTE: This section customizes this script to use hard-coded values for
#       CompressionMode & Loss(y)less ratios.
#       It is set to retain the compressed copy for gains as little as 1%.
CompressionMode="JPEG2000Lossless"
# CompressionMode="JPEGLossless"
MinLossyRatio="1.5"
MinLosslessRatio="1.01"

#[ -f "$ARCHIVE_VAR/archive.cfg" ] && . $ARCHIVE_VAR/archive.cfg
# /home/medsrv/var/arch/archive.cfg contents
# WarningLimit="60"
# ChangeLimit="85"
# EmptyMountPoints=""
# StopArchive="97"
# CompressionMode="JPEG2000Lossless"	<<<< Sourced for this
# MinLossyRatio="1.5"									<<<< Sourced for this
# MinLosslessRatio="1.1"							<<<< Sourced for this


LOGGER="/usr/bin/logger"
TAG="utils/compressObject[$$]"

ErrMsg=""

tabulation=""

# Parameters

Input=""

while getopts 'o:i:t:v' OPT; do
	case $OPT in
		i) Input="$OPTARG" ;;
		o) Output="$OPTARG" ;;
		t) tabulation="$OPTARG" ;;
		v) Verbose="true" ;;
		*) ErrMsg="Invalid_Parameter:$OPT" ;;
	esac
done

[ -z "$Output" ] && Output="$Input"

run_()
{
	if [ -z "$Input" ] ; then
		$LOGGER -p $LOG_FACILITY.err -t "$TAG" "missing parameter(s)"
		return 125
	fi

	if [ ! -f "$Input" ] ; then
		$LOGGER -p $LOG_FACILITY.err -t "$TAG" "Missing File $Input"
		return 125
	fi

	# Check if CompressionMode is set and compress DICOM file before putting to archive
	CompressedFile=""
	#[ -n "$Verbose" ] && echo "${tabulation}$CompressionMode"
  #echo "${tabulation}$CompressionMode"
	[ "$CompressionMode" = "None" ] && return 0

	# Check if the DICOM file contains Pixel Data at all and if it's already compressed or not
	# dump TS and pixel data
	# (0002,0010) Transfer Syntax UID
	# (0008,0060) Modality
	# (7fe0,0010) Pixel Data
 	ImageInfo=`$DCMTK_HOME/bin/dcmdump +P "0008,0060" +P "0002,0010" +P "7fe0,0010" $Input 2>/dev/null`

	#[ -n "$Verbose" ] && echo "$ImageInfo"

	if ! grep -q "7fe0,0010" <<<"$ImageInfo"; then
		[ -n "$Verbose" ] && echo "${tabulation}$(basename $Input) - no image..."
        #echo "${tabulation}$(basename $Input) - no image..."
		return 0
	fi

  currentCompression=$(echo "$ImageInfo" | grep "0002,0010" | awk '{print $1, $2, $3}')

	if ! grep -q "0002,0010.*Endian" <<<"$ImageInfo"; then
		[ -n "$Verbose" ] && echo "${tabulation}$(basename $Input) - Already Compressed/Encapsulated...$currentCompression"
        #echo "${tabulation}$(basename $Input) - Already Compressed/Encapsulated...$currentCompression"
		return 0
	fi


	CompressedTempFile="$TMP/compressObject.sh.$$"
	objdiffFlag=""
  # COMPERSS VIA JPEGLOSSLESS
	if [ "$CompressionMode" = "JPEGLossless" -o "$CompressionMode" = "JPEGLosslessSV1" ] ; then
		CompFlag="+e1"
		[ "$CompressionMode" = "JPEGLossless" ] && CompFlag="+el"
		if grep -q "0008,0060.*US.*" <<<"$ImageInfo"; then
			#CompFlag="+eb --color-rgb --uid-never"
			#echo "Skipping compression on US exams..."
			exit 1
		fi
        echo "${tabulation}command: dcmcjpeg ${CompFlag} $Input ${CompressedTempFile}"
		$DCMTK_HOME/bin/dcmcjpeg ${CompFlag} $Input ${CompressedTempFile} #2>/dev/null
		if [ $? -ne 0 ] ; then
			[ -f "${CompressedTempFile}" ] && rm "${CompressedTempFile}"
			[ -n "$Verbose" ] && echo "${tabulation}$(basename $Input) - compression failed"
            #echo "${tabulation}$(basename $Input) - compression failed"
			return 1
		fi
	fi

  # COMPRESS VIA JPEG2000LOSLESS
	if [ "$CompressionMode" = "JPEG2000Lossless" -o "$CompressionMode" = "JPEG2000Lossy" ] ; then
		CompFlag="+tl"
		if [ "$CompressionMode" = "JPEG2000Lossy" ] ; then
			CompFlag="+ty"
			isLossy="true"
		fi
    if grep -q "0008,0060.*US.*" <<<"$ImageInfo"; then
			#CompFlag="+eb --color-rgb --uid-never"
			#echo "Skipping compression on US exams..."
			exit 1
		fi
    #echo "${tabulation}command: convert ${CompFlag} ${Input} ${CompressedTempFile}"                                                                              
		$UTILS_HOME/bin/convert ${CompFlag} ${Input} ${CompressedTempFile} 2>/dev/null
		if [ $? -ne 0 ] ; then
			[ -f "${CompressedTempFile}" ] && rm "${CompressedTempFile}"
			[ -n "$Verbose" ] && echo "${tabulation}$(basename $Input) - compression failed"
            #echo "${tabulation}$(basename $Input) - compression failed"
			return 1
		fi
	fi


	### CHECK IF COMPRESSED FILE IS EQUIVALENT TO THE ORIGINAL ONE
  #echo "${tabulation}command: objdiff ${Input} ${CompressedTempFile}"
	$UTILS_HOME/bin/objdiff ${Input} ${CompressedTempFile} #>/dev/null 2>&1
	if [ $? -ne 0 ] ; then
		[ -f "${CompressedTempFile}" ] && rm "${CompressedTempFile}"
		[ -n "$Verbose" ] && echo "${tabulation}$(basename $Input) - objdiff failed (${CompressedTempFile})"
        #echo "${tabulation}$(basename $Input) - objdiff failed (${CompressedTempFile})"
		return 1
	fi

	CompressedFile="$CompressedTempFile"


	#### CHECK IF THE COMPRESSED FILE IS SMALL ENOUGH
	origSize=`ls -l "$Input" | awk '{print $5}'`
	compSize=`ls -l "$CompressedFile" | awk '{print $5}'`
	ratio="$MinLossyRatio"
	[ -z $isLossy ] && ratio="$MinLosslessRatio"

  beforeUnit="Bytes"
  afterUnit="Bytes"
  origSize_KB=0
  origSize_MB=0
  if [[ $origSize -ge 1024 ]]; then
    origSize_KB=$((origSize / 1024))
    beforeSize=$origSize_KB
    beforeUnit="KB"
    if [[ $origSize_KB -ge 1024 ]]; then
      origSize_MB=$((origSize / 1024 / 1024))
      beforeSize=$origSize_MB
      beforeUnit="MB"
    fi
  fi
  if [[ $compSize -ge 1024 ]]; then
    compSize_KB=$((compSize / 1024))
    afterSize=$compSize_KB
    afterUnit="KB"
    if [[ $compSize_KB -ge 1024 ]]; then
      compSize_MB=$((compSize / 1024 / 1024))
      afterSize=$compSize_MB
      afterUnit="MB"
    fi
  fi

  # origSize_fmt=$(numfmt --grouping $origSize)
  # compSize_fmt=$(numfmt --grouping $compSize)
  # origSize_KB_fmt=$(numfmt --grouping $origSize_KB)
  # compSize_KB_fmt=$(numfmt --grouping $compSize_KB)

  # # Asses if compressed size is smaller than original size
  # awk -v orig="$origSize" -v comp="$compSize" -v ratio="$ratio"  'BEGIN { if ( orig < comp*ratio) exit 1 } '
	# if [ $? != 0 ] ; then # COMPRESSED FILE IS GREATER THAN OR EQUAL TO SIZE OF ORIGINAL
		# # we don't use the compressed form, because we don't gain enough space 
		# #[ -n "$Verbose" ] && echo "${tabulation}compressed size($compSize) is greater than original size ($origSize) * ratio ($ratio)"
    # echo "${tabulation}$Input - compressed size($afterSize $afterUnit) is greater than original size ($beforeSize $beforeUnit) * ratio ($ratio)"
		# [ -f "${CompressedFile}" ] && rm "${CompressedFile}"
		# return 1
  # else
    # echo "${tabulation}$Input - Compression success. Original size ($beforeSize $beforeUnit) - Compressed size($afterSize $afterUnit)."
	# fi
  
  
  # COMPRESSION RATIO
  # Compression Ratio = Uncompressed_Size divided by Compressed_Size
  # Compression Ratio = $origSize / $compSize
  #compRatio=$(echo "scale=2; ($origSize / $compSize)" | bc | sed '/\./ s/\.\{0,1\}0\{1,\}$//')
  
  # SPACE SAVINGS
  # Space Savings = Compressed_Size divided by Uncompressed_Size
  # Space Savings = $compSize / $origSize
  #spaceSavings=$(echo "scale=2; ($compSize / $origSize)" | bc | sed '/\./ s/\.\{0,1\}0\{1,\}$//')
  
  # Asses if compressed size is smaller than original size
  #JB: Keep compressed file if it's smaller at all.
  if [[ $compSize -lt $origSize ]]; then
    compRatio=$(echo "scale=2; ($origSize / $compSize)" | bc | sed '/\./ s/\.\{0,1\}0\{1,\}$//')
    spaceSavings=$(echo "scale=4; 100*(1-($compSize / $origSize))" | bc | sed '/\./ s/\.\{0,1\}0\{1,\}$//')
    if [[ "$Verbose" == "true" ]]; then
      #echo "${tabulation}$Input - Compression success. Original size ($origSize_fmt Bytes (${origSize_KB_fmt} KB OR ${origSize_MB} MB)) - Compressed size ($compSize_fmt Bytes (${compSize_KB_fmt} KB OR ${compSize_MB} MB)). $compRatio ratio, ${spaceSavings}% space saved."
      #echo "${tabulation}$Input - Compression success. Original size ($origSize Bytes (${origSize_KB} KB OR ${origSize_MB} MB)) - Compressed size ($compSize Bytes (${compSize_KB} KB OR ${compSize_MB} MB)). $compRatio ratio, ${spaceSavings}% space saved."
      echo "${tabulation}$(basename $Input) - Compression success. FROM $beforeSize $beforeUnit TO $afterSize ${afterUnit}, RATIO ${compRatio}, SAVED SPACE ${spaceSavings}%."
    #else
      #echo "${tabulation}$(basename $Input) - Compression success. FROM $beforeSize $beforeUnit TO $afterSize ${afterUnit}, RATIO ${compRatio}, SAVED SPACE ${spaceSavings}%."
    fi
  else # COMPRESSED FILE IS GREATER THAN OR EQUAL TO SIZE OF ORIGINAL
    # we don't use the compressed form, because we don't gain any space
    [[ "$Verbose" == "true" ]] && echo "${tabulation}$(basename $Input) - compressed size($afterSize $afterUnit) is greater than original size ($beforeSize $beforeUnit)"
    [ -f "${CompressedFile}" ] && rm "${CompressedFile}"
    return 1
  fi
  
	if [ -n "${CompressedFile}" ] ; then 
		OutputTmp="${Output}.compressed.$$"
		cp -f $CompressedFile $OutputTmp
		cmp -s $CompressedFile $OutputTmp
		if [ $? != 0 ] ; then
			[ -n "$Verbose" ] && echo "${tabulation}$(basename $Input) - Copying compressed object to target directory failed."
            #echo "${tabulation}$(basename $Input) - Copying compressed object to target directory failed."
			[ -f "${CompressedFile}" ] && rm "${CompressedFile}"
			[ -f "${OutputTmp}" ] && rm "${OutputTmp}"
			return 1
		fi
    
		rm ${CompressedFile}
		[ -f "$Output" ] && mv "$Output" "$Output.orig.$$"
		mv "$OutputTmp" "$Output"
		if [ $? == 0 ] ; then
			rm "$Output.orig.$$" 2>/dev/null
		else
			[ -n "$Verbose" ] && echo "${tabulation}$(basename $Input) - Renaming temp file to $Output failed."
            #echo "${tabulation}$(basename $Input) - Renaming temp file to $Output failed."
			return 1
		fi
	fi
	return 0
}

# override print_
print_()
{
	echo "Compressing $(basename $Input)"
}


get_watson_message_()
{
	if [ "$RUN_RESULT" -gt 124 ] ; then
		WATSON_MESSAGE_ID="compress.$Input.failed"
		WATSON_MESSAGE_TEXT="FAILED: compressing $(basename $Input)"
		return
	fi

	if [ "$RUN_RESULT" -ne 0 -a "$RETRY_NUM" -gt 0 -a $(( $RETRY_NUM % 10)) -eq 0 ] ; then
		WATSON_MESSAGE_ID="compress.$Input.$RETRY_NUM"
		WATSON_MESSAGE_TEXT="ERROR: compressing $(basename $Input) [Retry #$RETRY_NUM]"
	fi
}

run_
