#!/bin/bash

# DCM_TAG   VR  Name
# 0008,0052 CS  Query/Retrieve Level
# 0020,000D UI  Study Instance UID
# 0020,1208 IS  Number of Study Related Series
# 0008,0020 DA  Study Date
# 0008,0061 TM  Study Time
# 0008,0050 SH  Accession Number
# 0010,0020 LO  Patient ID

# CFind_StudyInfo_For_SUID() {
# 	set -e # This erronexit stays. Only effects this function.
# 	if ! /home/medsrv/component/dicom/bin/findscu -S --aetitle "$_LOCAL_AE_TITLE" --key 0008,0052=STUDY --key 0020,000D="$1" --key 0020,1208 --key 0008,0020 --key 0008,0061 --key 0008,0050 --key 0010,0020 --call $2 $3 $4; then
# 		# return 1
# 		exit 1
# 	fi
# }

# Extract_DCM_Tag_Values_From_FindSCU_Response "$(CFind_StudyInfo_For_SUID "$Study" "$Source_AET" "$Source_IP" "$Source_Port")"

# Extract_DCM_Tag_Values_From_FindSCU_Response() {
# 	findscu_response="$1"
# 	# Use grep and cut to extract the relevant information from the file
# 	PatientID=$(printf "%s" "$findscu_response" | grep "(0010,0020)\|PatientID" | cut -d ' ' -f 3 | tr -d '[]')
# 	NumberOfStudyRelatedInstances="$(printf "%s" "$findscu_response" | grep "(0020,1208)\|NumberOfStudyRelatedInstances" | cut -d ' ' -f 3 | tr -d '[]')"
# 	StudyDate="$(printf "%s" "$findscu_response" | grep "(0008,0020)\|StudyDate" | cut -d ' ' -f 3 | tr -d '[]')"
# 	Modality="$(printf "%s" "$findscu_response" | grep "(0008,0061)\|Modality" | cut -d ' ' -f 3 | tr -d '[]')"
# 	AccessionNumber="$(printf "%s" "$findscu_response" | grep "(0008,0050)\|AccessionNumber" | cut -d ' ' -f 3 | tr -d '[]')"
# 	# TODO - Add these if possible
# 	# sumsize
# 	# mainst
# 	# Dcstudy_D
# 	# EXAMPLE
# 		# [medsrv@Migration-Team-PACS-Hub1-v8 ~]$ /home/medsrv/component/dicom/bin/findscu -S --aetitle JBHUB1 --key 0008,0052=STUDY --key 0020,000D=1.2.124.113532.32961.28196.61186.20150706.65653.3097184759 --key 0020,1208 --key 0008,0020 --key 0008,0061 --key 0008,0050 --key 0010,0020 --call v7source 10.240.24.223 104
# 		# RESPONSE: 1(Pending)

# 		# # Dicom-Data-Set
# 		# # Used TransferSyntax: Little Endian Explicit
# 		# (0008,0020) DA [20150706]                               #   8, 1 StudyDate
# 		# (0008,0050) SH [184905]                                 #   6, 1 AccessionNumber
# 		# (0008,0052) CS [STUDY]                                  #   6, 1 QueryRetrieveLevel
# 		# (0008,0054) AE [v7source]                               #   8, 1 RetrieveAETitle
# 		# (0008,0061) CS [PT]                                     #   2, 1 ModalitiesInStudy
# 		# (0010,0020) LO [184905]                                 #   6, 1 PatientID
# 		# (0020,000d) UI [1.2.124.113532.32961.28196.61186.20150706.65653.3097184759] #  58, 1 StudyInstanceUID
# 		# (0020,1208) IS [141]                                    #   4, 1 NumberOfStudyRelatedInstances
# 		# --------
# 		# [medsrv@Migration-Team-PACS-Hub1-v8 ~]$ /home/medsrv/component/dicom/bin/findscu -S --aetitle JBHUB1 --key 0008,0052=STUDY --key 0020,000D=1.2.124.113532.32961.28196.61186.20150706.65653.3097184759 --key 0020,1208 --key 0008,0020 --key 0008,0061 --key 0008,0050 --key 0010,0020 --call v7source 10.240.24.223 104 | grep -o "(0008,0020) DA \[.*\]\|(0008,0050) SH \[.*\]\|(0008,0061) CS \[.*\]\|(0010,0020) LO \[.*\]\|(0020,1208) IS \[.*\]" | cut -d "[" -f2 | cut -d "]" -f1
# 		# 20150706
# 		# 184905
# 		# PT
# 		# 184905
# 		# 141
# 		# [medsrv@Migration-Team-PACS-Hub1-v8 ~]$
# }

ARBITRARY_AET=""
Study_Instance_UID=""
QUERY_AET=""
QUERY_IP=""
QUERY_PORT=""

# No SSL
/home/medsrv/component/dicom/bin/findscu -S --aetitle $ARBITRARY_AET --key 0008,0052=STUDY --key 0020,000D=$Study_Instance_UID --key 0020,1208 --key 0008,0020 --key 0008,0061 --key 0008,0050 --key 0010,0020 --call $QUERY_AET $QUERY_IP $QUERY_PORT

# SSL
/home/medsrv/component/dicom/bin/findscu -S +tls "$SSL_SITE_KEY" "$SSL_SITE_CERT" -ic +ps --aetitle $ARBITRARY_AET --key 0008,0052=STUDY --key 0020,000D=$Study_Instance_UID --key 0020,1208 --key 0008,0020 --key 0008,0061 --key 0008,0050 --key 0010,0020 --call $QUERY_AET $QUERY_IP $QUERY_PORT