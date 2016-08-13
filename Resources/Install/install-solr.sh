#!/usr/bin/env bash

clear

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
EXTENSION_ROOTPATH="$SCRIPTPATH/../../"

SOLR_VERSION=6.1.0
EXT_SOLR_VERSION=6.0
JAVA_VERSION=8
SOLR_INSTALL_DIR="/opt/solr"
SOLR_PORT=8983

APACHE_MIRROR="http://mirror.dkd.de/apache/"
APACHE_ARCHIVE="http://archive.apache.org/dist/"

# ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----

progressfilt ()
{
	local flag=false c count cr=$'\r' nl=$'\n'
	while IFS='' read -d '' -rn 1 c
	do
		if $flag
		then
			printf '%c' "$c"
		else
			if [[ $c != $cr && $c != $nl ]]
			then
				count=0
			else
				((count++))
				if ((count > 1))
				then
					flag=true
				fi
			fi
		fi
	done
}

# check whether a given resource is available on a mirror
# if the resource is found it will download from the mirror
# it the resource is not found it will download from Apache archive
apachedownload ()
{
	# test mirror
	wget -q --spider "$APACHE_MIRROR$1"

	if [ $? -eq "0" ]
	then
		# download from mirror
		wget --progress=bar:force "$APACHE_MIRROR$1" 2>&1 | progressfilt
	else
		# download from archive
		wget --progress=bar:force "$APACHE_ARCHIVE$1" 2>&1 | progressfilt
	fi
}

# ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----

# color echo http://www.faqs.org/docs/abs/HTML/colorizing.html

black="\033[30m"
red="\033[31m"
green="\033[32m"
yellow="\033[33m"
blue="\033[34m"
magenta="\033[35m"
cyan="\033[36m"
white="\033[37m"


# Color-echo, Argument $1 = message, Argument $2 = color
cecho ()
{
	local default_msg="No message passed."

	# Defaults to default message.
	message=${1:-$default_msg}

	# Defaults to black, if not specified.
	color=${2:-$black}

	echo -e "$color$message"

	# Reset text attributes to normal + without clearing screen.
	tput sgr0

	return
}

# ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----

while getopts :p:d: FLAG; do
  case $FLAG in
    d)
      SOLR_INSTALL_DIR=$OPTARG
      ;;
    \?) #unrecognized option - show help
      exit 2
      ;;
  esac
done

cecho "####################################################################" $red
cecho "# This script should be used for development only!                 #" $red
cecho "#                                                                  #" $red
cecho "# It contains no:                                                  #" $red
cecho "# - Security Updates                                               #" $red
cecho "# - Init Scripts                                                   #" $red
cecho "# - Upgrade possibilities                                          #" $red
cecho "#                                                                  #" $red
cecho "####################################################################" $red

cecho "Starting installation of Apache Solr with the following settings:" $green
cecho "Solr Version: ${SOLR_VERSION}                                    " $green
cecho "Installation Path: ${SOLR_INSTALL_DIR}                           " $green

# ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----

cecho "Checking requirements." $green

PASSALLCHECKS=1

if [ ! -w "$(dirname $SOLR_INSTALL_DIR)" ]
then
	cecho "ERROR parent directory: ($(dirname $SOLR_INSTALL_DIR)) of install path ($SOLR_INSTALL_DIR) is not writeable." $red
	PASSALLCHECKS=0
fi

wget --version > /dev/null 2>&1
CHECK=$?
if [ $CHECK -ne "0" ]
then
	cecho "ERROR couldn't find wget." $red
	PASSALLCHECKS=0
fi

java -version > /dev/null 2>&1
CHECK=$?
if [ $CHECK -ne "0" ]
then
	cecho "ERROR couldn't find Java (Oracle Java is recommended)." $red
	PASSALLCHECKS=0
fi

JAVA_VERSION_INSTALLED=$(java -version 2>&1 | grep -Eom1 "[._0-9]{5,}")
# extract the main Java version from 1.7.0_11 => 7
JAVA_VERSION_INSTALLED=${JAVA_VERSION_INSTALLED:2:1}

# check if java version is equal or higher then required
if [ $JAVA_VERSION_INSTALLED -lt $JAVA_VERSION ]
then
	cecho "You have installed Java version $JAVA_VERSION_INSTALLED. Please install Java $JAVA_VERSION or newer." $red
	PASSALLCHECKS=0
fi

ping -c 1 mirror.dkd.de > /dev/null 2>&1
CHECK=$?
if [ $CHECK -ne "0" ]
then
	cecho "ERROR couldn't ping Apache download mirror, try again using wget" $yellow
	wget -q --spider http://mirror.dkd.de/apache/
	if [ $? -ne "0" ]
	then
		cecho "ERROR Also couldn't reach the Apache download mirror using wget. Please check your internet connection." $red
		PASSALLCHECKS=0
	fi
fi

tar --version > /dev/null 2>&1
CHECK=$?
if [ $CHECK -ne "0" ]
then
	cecho "ERROR: couldn't find tar." $red
	PASSALLCHECKS=0
fi


if [ $PASSALLCHECKS -eq "0" ]
then
	cecho "Please install all missing requirements or fix any other errors listed above and try again." $red
	exit 1
else
	cecho "All requirements met, starting to install Solr." $green
fi

# ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----

mkdir $SOLR_INSTALL_DIR
cd $SOLR_INSTALL_DIR

cecho "Downloading Apache Solr $SOLR_VERSION" $green

if [ ! -f solr-$SOLR_VERSION.tgz ]; then
    apachedownload lucene/solr/$SOLR_VERSION/solr-$SOLR_VERSION.tgz
fi

cecho "Extracting downloaded solr $SOLR_VERSION" $green
tar -C $SOLR_INSTALL_DIR --extract --file "$SOLR_INSTALL_DIR/solr-$SOLR_VERSION.tgz" --strip-components=1

cecho "Adjusting solr configuration" $green
sed -i -e "s/#SOLR_PORT=8983/SOLR_PORT=$SOLR_PORT/" "$SOLR_INSTALL_DIR/bin/solr.in.sh"
sed -i -e '/-Dsolr.clustering.enabled=true/ a SOLR_OPTS="$SOLR_OPTS -Dsun.net.inetaddr.ttl=60 -Dsun.net.inetaddr.negative.ttl=60"' "$SOLR_INSTALL_DIR/bin/solr.in.sh"

cecho "Remove default configsets" $green
rm -fR ${SOLR_INSTALL_DIR}/server/solr/configsets

cecho "Copy configsets" $green
cp -r ${EXTENSION_ROOTPATH}/Resources/Solr/configsets ${SOLR_INSTALL_DIR}/server/solr

cecho "Copy copy solr.xml" $green
cp ${EXTENSION_ROOTPATH}/Resources/Solr/solr.xml ${SOLR_INSTALL_DIR}/server/solr/solr.xml

cecho "Create default cores" $green
cp -r ${EXTENSION_ROOTPATH}/Resources/Solr/cores ${SOLR_INSTALL_DIR}/server/solr

cecho "Setting environment" $green
source $SOLR_INSTALL_DIR/bin/solr.in.sh

cecho "Changing owner" $green
#chown -R $SOLR_USER:$SOLR_USER "$SOLR_INSTALL_DIR/solr"

cecho "Starting solr" $green
$SOLR_INSTALL_DIR/bin/solr start

cecho "Cleanup download" $green
rm $SOLR_INSTALL_DIR/solr-$SOLR_VERSION.tgz