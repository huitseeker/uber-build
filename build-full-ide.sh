#!/bin/bash -e

# If you wish to skip tests when building scala-refactoring, you can do so by setting the value of REFACTORING_MAVEN_ARGS=-Dmaven.test.skip=true, and pass it to the script.

###############################################################
#               Overridable Environment Methods               #
###############################################################

: ${DEBUG:=true}                  # Prints some additional information

: ${ECLIPSE:=eclipse}             # Eclipse executable
: ${SBT:=sbt}                     # Sbt executable
: ${MAVEN:=mvn}                   # Mvn executable
: ${MAVEN_EXTRA_ARGS:=}           # Maven extra arguments, like --batch (for Jenkins)
: ${GIT:=git}                     # Git executable
: ${KEYTOOL=keytool}              # Needed for signing the JARs

: ${SIGN_BUILD:=false}            # Should the IDE and its dependencies be signed. If you enable this, make sure to also provide a value for KEYSTORE_GIT_REPO and KEYSTORE_PASS, or the script will ask the user for these inputs
: ${KEYSTORE_GIT_REPO:=}          # URL to the Keystore Git repository
: ${KEYSTORE_PASS:=}              # Password for the Keystore

: ${VERSION_TAG:=}                # Version suffix to be appended to the IDE version number. When building a signed IDE, make sure to provide a value for the VERSION_TAG

: ${SCALA_VERSION:=}              # Scala version to use to build the IDE and all its dependencies
: ${SCALA_IDE_BRANCH:=}           # Scala IDE branch/tag to build
: ${SCALA_IDE_GIT_REPO:=git://github.com/scala-ide/scala-ide.git} 
: ${SCALARIFORM_GIT_REPO:=}       # Git repository to use to build scalariform
: ${SCALARIFORM_BRANCH:=}         # Scalariform branch/tag to build
: ${SCALA_REFACTORING_GIT_REPO:=} # Git repository to use to build scala-refactoring
: ${SCALA_REFACTORING_BRANCH:=}   # Scala-refactoring branch/tag to build
: ${SBT_GIT_REPO:=}               # Git repository to use to build sbt artifacts
: ${SBT_BRANCH:=}                 # Sbt branch/tag to build
: ${SBINARY_BRANCH:=}             # Sbinary branch/tag to build
: ${REFACTORING_MAVEN_ARGS:=""}   # Pass some maven argument to the scala-refactoring build, e.g. -Dmaven.test.skip=true

: ${ECLIPSE_PLATFORM:=}           # Pass the Eclipse platform (e.g., "indigo", or "juno")
: ${BUILD_PLUGINS:=false}         # Should we build worksheet and the Typesafe IDE product as well.
: ${WORKSHEET_BRANCH:=}           # Worksheet branch/tag to build
: ${TYPESAFE_IDE_BRANCH:=master}  # Typesafe IDE branch/tag to build (default is master)
: ${TYPESAFE_IDE_VERSION_TAG:=}   # Typesafe IDE version tag

export MAVEN_OPTS="-Xmx1500m"
export "$@" > /dev/null

###############################################################
#                          Global Methods                     #
###############################################################

# prints the script's arguments, one on every line, with escape
# sequences interpreted
function print_own_arguments()
{
    printf '"%b"\n' "$0" "$@" | nl -v0 -s": "
}

function abort()
{
    MSG=$1
    if [ "$MSG" ]; then
        echo >&2 "$MSG"
    fi
    echo "Abort."
    exit 1
}

function print_step()
{
    cat <<EOF

==================================================================
                     $1
==================================================================

EOF
}

# Check that the VERSION_TAG was provided. If not, abort.
function assert_version_tag_not_empty()
{
    if [[ -z "$VERSION_TAG" ]]
    then
        abort "VERSION_TAG cannot be empty."
    fi
}

# Check that the TYPESAFE_IDE_VERSION_TAG was provided. If not, abort.
function assert_typesafe_ide_version_tag_not_empty()
{
    if [[ -z "$TYPESAFE_IDE_VERSION_TAG" ]]
    then
        abort "TYPESAFE_IDE_VERSION_TAG cannot be empty."
    fi
}

function debug()
{
    MSG=$1
    if [[ $DEBUG ]]
    then
        echo $MSG
    fi
}

if [[ $DEBUG ]]
then
    print_own_arguments "$@"
fi
###############################################################
#                       SCALA VERSION                         #
###############################################################

if [[ -z "$SCALA_VERSION" ]]
then
    abort "SCALA_VERSION cannot be empty"
fi


case $SCALA_VERSION in

    2.9.* )
        scala_profile_ide=scala-2.9.x
        worksheet_scala_profile=2.9.x
        ECOSYSTEM_SCALA_VERSION=scala29
        REPO_SUFFIX=29x
        ;;

    2.10.* )
        scala_profile_ide=scala-2.10.x
        worksheet_scala_profile=2.10.x
        ECOSYSTEM_SCALA_VERSION=scala210
        REPO_SUFFIX=210x
        ;;

    2.11.* )
        scala_profile_ide=scala-2.11.x
        worksheet_scala_profile=2.11.x
        ECOSYSTEM_SCALA_VERSION=unknwon
        REPO_SUFFIX=211x
        ;;

    *)
        abort "Unknown scala version ${SCALA_VERSION}"
esac

###############################################################
#                       ECLIPSE PLATFORM                      #
###############################################################

if [[ -z "$ECLIPSE_PLATFORM" ]]
then
    abort "ECLIPSE_PLATFORM cannot be empty"
fi

case $ECLIPSE_PLATFORM in

    indigo )
        worksheet_eclipse_profile=indigo
        ecosystem_platform=e37
        ;;

    juno )
        worksheet_eclipse_profile=juno
        ecosystem_platform=e38
        ;;

    *)
        abort "Unknown Eclipse version ${ECLIPSE_PLATFORM}"
esac


###############################################################
#      Checks that the needed executables are available       #
###############################################################

function validate_java()
{
    (java -version 2>&1 | grep \"1.6.*\")
    if [[ $? -ne 0 ]]
    then
        java -version
        abort "Invalid Java version detected. Only java 1.6 is supported due to changes in jarsigner in 1.7"
    fi
}

# If passed executable's name is available return 0 (true), else return 1 (false).
# @param $1 The executable's name
function executable_in_path()
{
    CMD=$1
    RES=$(which $CMD)

    if [ "$RES" ]; then
        return 0
    else
        return 1
    fi
}

# Exit with code failure 1 if the executable is not available.
# @param $1 The executable's name
function assert_executable_in_path()
{
    CMD=$1
    (executable_in_path $CMD) || {
        abort "$CMD is not available."
    }
}

# Checks that all executables needed by this script are available
validate_java
assert_executable_in_path ${MAVEN}
assert_executable_in_path ${ECLIPSE}
assert_executable_in_path ${GIT}
assert_executable_in_path ${SBT}

############## Helpers #######################

SCALAIDE_DIR=scala-ide
SCALARIFORM_DIR=scalariform
SCALA_REFACTORING_DIR=scala-refactoring
SBINARY_DIR=sbinary
SBT_DIR=sbt
WORKSHEET_DIR=worksheet-plugin
TYPESAFE_IDE_DIR=typesafe-ide
KEYSTORE_FOLDER=typesafe-keystore

BASE_DIR=`pwd`
KEYSTORE_PATH="${BASE_DIR}/${KEYSTORE_FOLDER}/typesafe.keystore"

LOCAL_REPO=`pwd`/m2repo
SOURCE=${BASE_DIR}/p2-repo
PLUGINS=${SOURCE}/plugins
REPO_NAME=scala-eclipse-toolchain-osgi-${REPO_SUFFIX}
REPO=file://${SOURCE}/${REPO_NAME}
NEXT_BASE=${BASE_DIR}/next/base

# Expected locations where to find binaries of Scala IDE and Worksheet after each of the projects has been built
SCALA_IDE_BINARIES=${BASE_DIR}/${SCALAIDE_DIR}/org.scala-ide.sdt.update-site/target/site
WORKSHEET_BINARIES=${BASE_DIR}/${WORKSHEET_DIR}/org.scalaide.worksheet.update-site/target/site/
SDK_BINARIES=${BASE_DIR}/${TYPESAFE_IDE_DIR}/org.scala-ide.product/target/repository/

if $SIGN_BUILD
then
    MAVEN_SIGN_ARGS=" -Djarsigner.storepass=${KEYSTORE_PASS} -Djarsigner.keypass=${KEYSTORE_PASS} -Djarsigner.keystore=/${KEYSTORE_PATH} "
fi

function build_sbinary()
{
    # build sbinary
    print_step "sbinary"

    cd ${SBINARY_DIR}

    # maven style for the toolchain build
    $SBT "reboot full" clean "show scala-instance" "set every crossScalaVersions := Seq(\"${SCALA_VERSION}\")" \
        'set (version in core) ~= { v => v + "-pretending-SNAPSHOT" }' \
        'set every publishMavenStyle := true' \
        'set every resolvers := Seq("Sonatype OSS Snapshots" at "https://oss.sonatype.org/content/repositories/snapshots")' \
        "set every publishTo := Some(Resolver.file(\"Local Maven\",  new File(\"${LOCAL_REPO}\")))" \
        'set every crossPaths := true' \
        'set every scalaBinaryVersion <<= scalaVersion.identity' \
        'set (libraryDependencies in core) ~= { ld => ld flatMap { case dep if (dep.configurations.map(_ contains "test") getOrElse false)  => None; case dep => Some(dep) } }' \
        +core/publish


#SBT "reboot full" clean 
#'set every crossScalaVersions := Seq("2.10.1-SNAPSHOT", "2.9.3-SNAPSHOT", "2.11.0-SNAPSHOT")'
#'set every scalaBinaryVersion <<= scalaVersion.identity'
#'set (libraryDependencies in core) ~= { ld => ld flatMap { case dep if (dep.configurations.map(_ contains "test") getOrElse false)  => None; case dep => Some(dep) } }'
#'set every publishMavenStyle := true'
#'set every resolvers := Seq("Sonatype OSS Snapshots" at "https://oss.sonatype.org/content/repositories/snapshots")'
#'set every credentials := Seq(Credentials(Path.userHome / ".credentials"))'
#'set every publishTo <<= scalaVersion {v => Some("Typesafe IDE" at "https://typesafe.artifactoryonline.com/typesafe/" + (if (v contains "2.11") "ide-2.11" else if (v contains "2.10") "ide-2.10" else "ide-2.9"))}'
#+core/publish

    cd ${BASE_DIR}
}

function build_sbt()
{
    # build sbt
    print_step "Building Sbt"

    cd ${SBT_DIR}
    $SBT "reboot full" clean \
        "set every crossScalaVersions := Seq(\"${SCALA_VERSION}\")" \
        'set every publishMavenStyle := true' \
        'set every Util.includeTestDependencies := false' \
        "set every resolvers := Seq(\"Sonatype OSS Snapshots\" at \"https://oss.sonatype.org/content/repositories/snapshots\", \"local-maven\" at \"file://${LOCAL_REPO}\")" \
        'set artifact in (compileInterfaceSub, packageBin) := Artifact("compiler-interface")' \
        'set (libraryDependencies in compilePersistSub) ~= { ld => ld map { case dep if (dep.organization == "org.scala-tools.sbinary") && (dep.name == "sbinary") => dep.copy(revision = (dep.revision + "-pretending-SNAPSHOT")) ; case dep => dep } }' \
        "set every publishTo := Some(Resolver.file(\"Local Maven\",  new File(\"${LOCAL_REPO}\")))" \
        'set every crossPaths := true' \
        'set every scalaBinaryVersion <<= scalaVersion.identity' \
        'set artifact in (compileInterfaceSub, packageBin) := Artifact("compiler-interface")' \
        'set publishArtifact in (compileInterfaceSub, packageSrc) := false' \
        +classpath/publish +logging/publish +io/publish +control/publish +classfile/publish \
        +process/publish +relation/publish +interface/publish +persist/publish +api/publish \
        +compiler-integration/publish +incremental-compiler/publish +compile/publish        \
        +compiler-interface/publish

#SBT "reboot full" clean \
#'set every Util.includeTestDependencies := false' \
#'set every crossScalaVersions := Seq("2.10.1-SNAPSHOT", "2.9.3-SNAPSHOT")' \
#'set every scalaBinaryVersion <<= scalaVersion.identity' \
#'set every publishMavenStyle := true' \
#'set every resolvers <<= scalaVersion {v => Seq("Typesafe IDE" at "https://typesafe.artifactoryonline.com/typesafe/" + (if (v contains "2.10") "ide-2.10" else "ide-2.9"), "Sonatype OSS Snapshots" at "https://oss.sonatype.org/content/repositories/snapshots")}' \
#'set (libraryDependencies in compilePersistSub) ~= { ld => ld map { case dep if (dep.organization == "org.scala-tools.sbinary") && (dep.name == "sbinary") => dep.copy(revision = (dep.revision + "-pretending-SNAPSHOT")) ; case dep => dep } }' \
#'set artifact in (compileInterfaceSub, packageBin) := Artifact("compiler-interface")' \
#'set publishArtifact in (compileInterfaceSub, packageSrc) := false' \
#'set every crossPaths := true' \
#'set every credentials := Seq(Credentials(Path.userHome / ".credentials"))' \
#'set every publishTo <<= scalaVersion {v => Some("Typesafe IDE" at "https://typesafe.artifactoryonline.com/typesafe/" + (if (v contains "2.10") "ide-2.10" else "ide-2.9"))}' \
#+classpath/publish +logging/publish +io/publish +control/publish +classfile/publish +process/publish +relation/publish +interface/publish +persist/publish +api/publish +compiler-integration/publish +incremental-compiler/publish +compile/publish +compiler-interface/publish 

    cd ${BASE_DIR}
}

function build_toolchain()
{
    # build toolchain
    print_step "Building Toolchain"

    MAVEN_ARGS="-P ${scala_profile_ide} -Dmaven.repo.local=${LOCAL_REPO} -Drepo.typesafe=file://${LOCAL_REPO} ${MAVEN_EXTRA_ARGS} clean install"
    rm -rf ${SOURCE}/*

    cd ${SCALAIDE_DIR}
    ${MAVEN} -Dscala.version=${SCALA_VERSION} ${MAVEN_ARGS}

    cd org.scala-ide.build-toolchain
    ${MAVEN} -Dscala.version=${SCALA_VERSION} ${MAVEN_ARGS}

    cd ../org.scala-ide.toolchain.update-site
    ${MAVEN} -Dscala.version=${SCALA_VERSION} ${MAVEN_ARGS}

    # make toolchain repo

    rm -Rf ${SOURCE}/plugins
    mkdir -p ${PLUGINS}

    cp org.scala-ide.scala.update-site/target/site/plugins/*.jar ${PLUGINS}

    print_step "p2 toolchain repo"

    $ECLIPSE \
        -debug \
        -consolelog \
        -nosplash \
        -verbose \
        -application org.eclipse.equinox.p2.publisher.FeaturesAndBundlesPublisher \
        -metadataRepository ${REPO} \
        -artifactRepository ${REPO} \
        -source ${SOURCE} \
        -compress \
        -publishArtifacts

    cd ${BASE_DIR}
}

function build_refactoring()
{
    # build scala-refactoring
    print_step "Building scala-refactoring"

    cd ${SCALA_REFACTORING_DIR}
    GIT_HASH="`git log -1 --pretty=format:"%h"`"
    ${MAVEN} ${MAVEN_EXTRA_ARGS} -P ${scala_profile_ide} -Dscala.version=${SCALA_VERSION} $REFACTORING_MAVEN_ARGS -Drepo.scala-ide=file://${SOURCE} -Dmaven.repo.local=${LOCAL_REPO} -Dgit.hash=${GIT_HASH} clean package

    cd $BASE_DIR

    # make scala-refactoring repo

    REPO_NAME=scala-refactoring-${REPO_SUFFIX}
    REPO=file://${SOURCE}/${REPO_NAME}

    rm -rf ${SOURCE}/${REPO_NAME}
    mkdir -p ${SOURCE}/${REPO_NAME}
    cp -r scala-refactoring/org.scala-refactoring.update-site/target/site/* ${SOURCE}/${REPO_NAME}

#    $ECLIPSE \
#        -debug \
#        -consolelog \
#        -nosplash \
#        -verbose \
#        -application org.eclipse.equinox.p2.publisher.FeaturesAndBundlesPublisher \
#        -metadataRepository ${REPO} \
#        -artifactRepository ${REPO} \
#        -source ${SOURCE} \
#        -compress \
#        -publishArtifacts

    cd ${BASE_DIR}
}

function build_scalariform()
{
    # build scalariform
    print_step "Building Scalariform"
    cd ${SCALARIFORM_DIR}

    GIT_HASH="`git log -1 --pretty=format:"%h"`"

    ${MAVEN} ${MAVEN_EXTRA_ARGS} -P ${scala_profile_ide} -Dscala.version=${SCALA_VERSION} -Drepo.scala-ide=file://${SOURCE} -Dmaven.repo.local=${LOCAL_REPO} -Dgit.hash=${GIT_HASH} clean package

    rm -rf ${SOURCE}/scalariform-${REPO_SUFFIX}
    mkdir ${SOURCE}/scalariform-${REPO_SUFFIX}
    cp -r scalariform.update/target/site/* ${SOURCE}/scalariform-${REPO_SUFFIX}/

    cd ${BASE_DIR}
}

function build_ide()
{
    print_step "Building Scala IDE"

    cd ${SCALAIDE_DIR}

    if $SIGN_BUILD
    then
      export SET_VERSIONS="true"
    fi

    ./build-all.sh -P ${scala_profile_ide} -Dscala.version=${SCALA_VERSION} -Drepo.scala-ide.root=file://${SOURCE} -Drepo.typesafe=file://${LOCAL_REPO} -Dmaven.repo.local=${LOCAL_REPO} -Dversion.tag=${VERSION_TAG} -Drepo.scala-refactoring=file://${SOURCE}/scala-refactoring-${REPO_SUFFIX} -Drepo.scalariform=file://${SOURCE}/scalariform-${REPO_SUFFIX} clean install

    cd ${BASE_DIR}
}

function sign_ide()
{
    print_step "Signing"

    cd ${SCALAIDE_DIR}/org.scala-ide.sdt.update-site

    ECLIPSE_ALIAS=$ECLIPSE
    ECLIPSE=$(which $ECLIPSE_ALIAS) ./plugin-signing.sh ${KEYSTORE_PATH} typesafe ${KEYSTORE_PASS} ${KEYSTORE_PASS}

    cd ${BASE_DIR}
}

function build_worksheet_plugin()
{
    print_step "Building Worksheet"

    cd ${WORKSHEET_DIR}

    # First run the task for setting the (strict) bundles' version in the MANIFEST of the Worksheet plugin
	${MAVEN} ${MAVEN_EXTRA_ARGS} -Dtycho.localArtifacts=ignore -P set-versions -P ${worksheet_scala_profile} -P ${worksheet_eclipse_profile} -Drepo.scala-ide=file://${SCALA_IDE_BINARIES} -Dscala.version=${SCALA_VERSION} -Dmaven.repo.local=${LOCAL_REPO} -Dtycho.style=maven --non-recursive exec:java
    # Then build the Worksheet plugin
	${MAVEN} ${MAVEN_EXTRA_ARGS} -Dtycho.localArtifacts=ignore -P ${worksheet_scala_profile} -P ${worksheet_eclipse_profile} -Drepo.scala-ide=file://${SCALA_IDE_BINARIES} -Dscala.version=${SCALA_VERSION} -Dversion.tag=v -Dmaven.repo.local=${LOCAL_REPO} ${MAVEN_SIGN_ARGS} clean package

    cd ${BASE_DIR}
}

#
# Merge two P2 repositories
#
# $1 source directory
# $2 dest directory
function p2_merge()
{
    #build-tools project is needed to merge p2 repos
    BUILD_TOOLS_GIT_REPO=git://github.com/scala-ide/build-tools.git
    BUILD_TOOLS=master
    BUILD_TOOLS_DIR=build-tools

    clone_git_repo_if_needed ${BUILD_TOOLS_GIT_REPO} ${BUILD_TOOLS_DIR}
    checkout_git_repo ${BUILD_TOOLS_GIT_REPO} ${BUILD_TOOLS_DIR} ${BUILD_TOOLS}

    cd $BUILD_TOOLS_DIR
    cd maven-tool/merge-site # this folder contains the POM for merging update-sites

    # Merge to update sites
    ${MAVEN} ${MAVEN_EXTRA_ARGS} -Drepo.source=$1 -Drepo.dest=$2 package

    cd ${BASE_DIR}
}

function create_merged_update_site()
{
    TYPESAFE_IDE_MERGE_ECOSYSTEM_DIR=typesafe-ide-merge-ecosystem
    rm -rf $TYPESAFE_IDE_MERGE_ECOSYSTEM_DIR
    mkdir -p $TYPESAFE_IDE_MERGE_ECOSYSTEM_DIR

    # Merge the Scala IDE and Worksheet update-sites in $TYPESAFE_IDE_MERGE_ECOSYSTEM_DIR
    p2_merge ${SCALA_IDE_BINARIES} ${BASE_DIR}/${TYPESAFE_IDE_MERGE_ECOSYSTEM_DIR}
    p2_merge ${WORKSHEET_BINARIES} ${BASE_DIR}/${TYPESAFE_IDE_MERGE_ECOSYSTEM_DIR}

    cd ${BASE_DIR}
}

function build_typesafe_ide()
{
    print_step "Building Typesafe IDE"

    # First create a base ecosystem update-site that contains both the Scala IDE and Worksheet plugins
    create_merged_update_site

    cd ${TYPESAFE_IDE_DIR}

    # Build the Typesafe IDE
    ${MAVEN} ${MAVEN_EXTRA_ARGS} -Dtycho.localArtifacts=ignore  --non-recursive -Pconfigure -P${scala_profile_ide},${ECLIPSE_PLATFORM} -Dversion.tag=${TYPESAFE_IDE_VERSION_TAG} -Dscala.version=${SCALA_VERSION} -Dmaven.repo.local=${LOCAL_REPO} -Drepopath.platform="" -Drepopath.scala-ide.ecosystem="" -Drepo.scala-ide.root=file://${BASE_DIR}/$TYPESAFE_IDE_MERGE_ECOSYSTEM_DIR process-resources
    ${MAVEN} ${MAVEN_EXTRA_ARGS} -Dtycho.localArtifacts=ignore  -P${scala_profile_ide},${ECLIPSE_PLATFORM} -Dversion.tag=${TYPESAFE_IDE_VERSION_TAG} -Dscala.version=${SCALA_VERSION} -Dmaven.repo.local=${LOCAL_REPO} -Drepopath.scala-ide.ecosystem="" -Drepopath.platform="" -Drepo.scala-ide.root=file://${BASE_DIR}/$TYPESAFE_IDE_MERGE_ECOSYSTEM_DIR ${MAVEN_SIGN_ARGS} clean package

    cd ${BASE_DIR}
}

function prepare_nextBase()
{
    print_step "Preparing next base site in ${NEXT_BASE}"

    rm -rf ${NEXT_BASE}
    mkdir -p ${NEXT_BASE}

    p2_merge ${SCALA_IDE_BINARIES} ${NEXT_BASE}
    p2_merge ${SDK_BINARIES} ${NEXT_BASE}
}

# Publish to download.scala-ide.org
# $1 - root, "sdk" or "sdk/next"
# $2 - platform, "e37" or "e38"
# $3 - path, "dev" or "stable"
function publish_nextBase()
{
    upload_dir="scala-ide.dreamhosters.com/$1/$2/${ECOSYSTEM_SCALA_VERSION}/$3/base"

    print_step "Publishing to $upload_dir"
    ssh scalaide@scala-ide.dreamhosters.com rm -rf $upload_dir
    scp -r $NEXT_BASE scalaide@scala-ide.dreamhosters.com:$upload_dir
    ssh scalaide@scala-ide.dreamhosters.com chmod -R g+rw $upload_dir
}

# Publish to download.scala-ide.org
# $1 - root, "releases" or "test"
# $2 - platform, "e37" or "e38"
function publish_worksheet()
{
    upload_dir="scala-ide.dreamhosters.com/plugins/worksheet/$1/$2/${worksheet_scala_profile}/site"

    print_step "Publishing to $upload_dir"
    ssh scalaide@scala-ide.dreamhosters.com rm -rf $upload_dir
    scp -r $WORKSHEET_BINARIES scalaide@scala-ide.dreamhosters.com:$upload_dir
    ssh scalaide@scala-ide.dreamhosters.com chmod -R g+rw $upload_dir
}

function build_plugins()
{
    build_worksheet_plugin
    build_typesafe_ide
}

###############################################################
#                          GIT Helpers                        #
###############################################################

function clone_git_repo_if_needed()
{
    GITHUB_REPO=$1
    FOLDER_DIR=$2

    if [ ! -d "$FOLDER_DIR" ]; then
        $GIT clone $GITHUB_REPO $FOLDER_DIR
    else
        cd $FOLDER_DIR
        git remote rm origin
        git remote add origin $GITHUB_REPO
        git fetch $NAME_REMOTE > /dev/null # Swallow output
        git fetch --tags $NAME_REMOTE > /dev/null # Swallow output
        cd $BASE_DIR
    fi
}

function exist_branch_in_repo()
{
    BRANCH=$1
    GIT_REPO=$2

    ESCAPED_BRANCH=`echo $BRANCH | sed -e 's/[\/&]/\\\&/g'`
    # Checks if it exists a remote branch that matches ESCAPED_BRANCH
    REMOTES=`$GIT ls-remote $GIT_REPO | awk '/'$ESCAPED_BRANCH'/ {print $2}'`
    if [[ "$REMOTES" ]]; then
        return 0
    else
        return 1
    fi
}

function exist_branch_in_repo_verbose()
{
    BRANCH=$1
    GIT_REPO=$2

    debug "Checking if branch $BRANCH exists in git repo ${GIT_REPO}..."
    if exist_branch_in_repo $BRANCH $GIT_REPO
    then
        debug "Branch found!"
        return 0
    else
        debug "Branch NOT found!"
        return 1
    fi
}

function assert_branch_in_repo_verbose()
{
    BRANCH=$1
    GIT_REPO=$2
    (exist_branch_in_repo_verbose $BRANCH $GIT_REPO) || abort
}

# Check that there are no uncommitted changes in $1
function validate()
{
    IGNORED_FILES_REGEX='^\.classpath$'
    # count the number of entries which doesn't match the regex
    COUNT=`(
        cd $1
        $GIT status --porcelain | awk "BEGIN {count = 0} {if (!match(\\\$2, \"${IGNORED_FILES_REGEX}\")) {count= count + 1;}} END {print count;}"
    )`

    if [[ $COUNT -ne 0 ]]; then
        echo -e "\nYou have uncommitted changes in $1:\n"
        (cd $1 && $GIT status | grep -v ${IGNORED_FILES_REGEX})
        abort
    fi
}

function checkout_git_repo()
{
    GITHUB_REPO=$1
    FOLDER_DIR=$2
    BRANCH=$3

    cd $FOLDER_DIR

    # clean-up all local changes
    git clean -d -f
    git reset --hard

    REFS=`$GIT show-ref $BRANCH | awk '{split($0,a," "); print a[2]}' | awk '{split($0,a,"/"); print a[2]}'`
    if [[ "$REFS" = "tags" ]]; then
        debug "In $FOLDER_DIR, checking out tag $BRANCH"
        $GIT checkout -q $BRANCH
    else
        FULL_BRANCH_NAME=origin/$BRANCH
        debug "In $FOLDER_DIR, checking out branch $FULL_BRANCH_NAME"
        $GIT checkout -q $FULL_BRANCH_NAME
    fi

    cd $BASE_DIR
    validate ${FOLDER_DIR}
}

###############################################################
#                          SIGNING                            #
###############################################################

if $SIGN_BUILD
then
    assert_executable_in_path ${KEYTOOL} # Check that keytool executable is available
    assert_version_tag_not_empty

    # Check if the keystore folder has been already pulled
    if [ ! -d "$KEYSTORE_FOLDER" ]; then
        if [[ -z "$KEYSTORE_GIT_REPO" ]]; then
            read -p "Please, provide the URL to the keystore git repository: " git_repo; echo
            KEYSTORE_GIT_REPO="$git_repo"
        fi
        clone_git_repo_if_needed $KEYSTORE_GIT_REPO $KEYSTORE_FOLDER
    fi

    # Password for using the keystore
    if [[ -z "$KEYSTORE_PASS" ]]; then
        read -s -p "Please, provide the password for the keystore: " passw; echo
        KEYSTORE_PASS=$passw
    fi

    # Check that the password to the keystore is correct (or fail fast)
    $KEYTOOL -list -keystore ${KEYSTORE_PATH} -storepass ${KEYSTORE_PASS} -alias typesafe
else
    echo "The IDE build will NOT be signed."
    if [[ -z $VERSION_TAG ]]; then
        VERSION_TAG=local
    fi
fi

###############################################################
#                            BUILD                            #
###############################################################

# At this point the version tag cannot be empty. Why? Because if the IDE build won't be signed,
# then VERSION_TAG is set to `local`. Otherwise, if the IDE build will be signed, then the
# VERSION_TAG must be set or the build will stop immediately.
# This is really just a sanity check.
assert_version_tag_not_empty

# These are currently non-overridable defaults
SBINARY_GIT_REPO=git://github.com/scala-ide/sbinary.git
WORKSHEET_GIT_REPO=git://github.com/scala-ide/scala-worksheet.git
TYPESAFE_IDE_GIT_REPO=git://github.com/typesafehub/scala-ide-product.git

if [[ ( -z "$SCALARIFORM_GIT_REPO" ) && ( -z "$SCALA_REFACTORING_GIT_REPO" ) && ( -z "$SBT_GIT_REPO" ) ]]
then
    read -n1 -p "Do you want to build the IDE dependencies using the original repositories, or the GitHub forks under the scala-ide organization? (o/f): " original_or_fork; echo;
    SCALA_REFACTORING_GIT_REPO=git://github.com/scala-ide/scala-refactoring.git

    case "$original_or_fork" in

    o )
        debug "Using the original repositories"
        SCALARIFORM_GIT_REPO=git://github.com/mdr/scalariform.git
        SBT_GIT_REPO=git://github.com/sbt/sbt.git
        ;;

    f )
        debug "Using the GitHub forks for $SCALARIFORM_DIR and $SBT_GIT_REPO"
        SCALARIFORM_GIT_REPO=git://github.com/scala-ide/scalariform.git
        SBT_GIT_REPO=git://github.com/scala-ide/xsbt.git
        ;;

    *)
        abort "Unexpected input. Found '$original_or_fork', expected 'o', for the original repositories, or 'f' for the forks."
        ;;

  esac
fi

clone_git_repo_if_needed ${SBINARY_GIT_REPO} ${SBINARY_DIR}
clone_git_repo_if_needed ${SBT_GIT_REPO} ${SBT_DIR}
clone_git_repo_if_needed ${SCALA_IDE_GIT_REPO} ${SCALAIDE_DIR}
clone_git_repo_if_needed ${SCALARIFORM_GIT_REPO} ${SCALARIFORM_DIR}
clone_git_repo_if_needed ${SCALA_REFACTORING_GIT_REPO} ${SCALA_REFACTORING_DIR}
clone_git_repo_if_needed ${WORKSHEET_GIT_REPO} ${WORKSHEET_DIR}
clone_git_repo_if_needed ${TYPESAFE_IDE_GIT_REPO} ${TYPESAFE_IDE_DIR}

if [[ ( -z "$SCALA_IDE_BRANCH" ) ]]; then
    read -p "What branch/tag should I use for building the ${SCALAIDE_DIR}: " scala_ide_branch;
    SCALA_IDE_BRANCH=$scala_ide_branch
    assert_branch_in_repo_verbose $SCALA_IDE_BRANCH $SCALA_IDE_GIT_REPO
fi

if [[ ( -z "$SCALARIFORM_BRANCH" ) ]]; then
    read -p "What branch/tag should I use for building ${SCALARIFORM_DIR}: " scalariform_branch;
    SCALARIFORM_BRANCH=$scalariform_branch
    assert_branch_in_repo_verbose $SCALARIFORM_BRANCH $SCALARIFORM_GIT_REPO
fi

if [[ ( -z "$SCALA_REFACTORING_BRANCH" ) ]]; then
    read -p "What branch/tag should I use for building ${SCALA_REFACTORING_DIR}: " scala_refactoring_branch;
    SCALA_REFACTORING_BRANCH=$scala_refactoring_branch
    assert_branch_in_repo_verbose $SCALA_REFACTORING_BRANCH $SCALA_REFACTORING_GIT_REPO
fi

if [[ ( -z "$SBINARY_BRANCH" ) ]]; then
    read -p "What branch/tag should I use for building ${SBINARY_DIR}: " sbinary_branch;
    SBINARY_BRANCH=$sbinary_branch
    assert_branch_in_repo_verbose $SBINARY_BRANCH $SBINARY_GIT_REPO
fi

if [[ ( -z "$SBT_BRANCH" ) ]]; then
    read -p "What branch/tag should I use for building ${SBT_DIR}: " sbt_branch;
    SBT_BRANCH=$sbt_branch
    assert_branch_in_repo_verbose $SBT_BRANCH $SBT_GIT_REPO
fi

if $BUILD_PLUGINS && [[ -z "$WORKSHEET_BRANCH" ]]
then
    read -p "What branch/tag should I use for building ${WORKSHEET_DIR}: " worksheet_branch;
    WORKSHEET_BRANCH=$worksheet_branch
    assert_branch_in_repo_verbose $WORKSHEET_BRANCH $WORKSHEET_GIT_REPO
fi

echo -e "Build configuration:"
echo -e "----------------------------------------------\n"
echo -e "Sbt               : ${SBT}"
echo -e "Scala version     : ${SCALA_VERSION}"
echo -e "Version tag       : ${VERSION_TAG}"
echo -e "P2 repo           : ${SOURCE}"
echo -e "Toolchain repo    : ${REPO}"

echo -e "SBinary           : ${SBINARY_DIR}, \t\tbranch: ${SBINARY_BRANCH}, repo: ${SBINARY_GIT_REPO}"
echo -e "Sbt               : ${SBT_DIR}, \t\tbranch: ${SBT_BRANCH}, repo: ${SBT_GIT_REPO}"
echo -e "Scalariform       : ${SCALARIFORM_DIR}, \tbranch: ${SCALARIFORM_BRANCH}, repo: ${SCALARIFORM_GIT_REPO}"
echo -e "Scala-refactoring : ${SCALA_REFACTORING_DIR}, \tbranch: ${SCALA_REFACTORING_BRANCH}, repo: ${SCALA_REFACTORING_GIT_REPO}"
echo -e "Scala IDE         : ${SCALAIDE_DIR}, \t\tbranch: ${SCALA_IDE_BRANCH}, repo: ${SCALA_IDE_GIT_REPO}"
if $BUILD_PLUGINS
then
    echo -e "Worksheet         : ${WORKSHEET_DIR}, \tbranch: ${WORKSHEET_BRANCH}, repo: ${WORKSHEET_GIT_REPO}"
    echo -e "Typesafe IDE      : ${TYPESAFE_IDE_DIR}, \tbranch: ${TYPESAFE_IDE_BRANCH}, repo: ${TYPESAFE_IDE_GIT_REPO}"
fi
echo -e "----------------------------------------------\n"

checkout_git_repo ${SBINARY_GIT_REPO} ${SBINARY_DIR} ${SBINARY_BRANCH}
checkout_git_repo ${SBT_GIT_REPO} ${SBT_DIR} ${SBT_BRANCH}
checkout_git_repo ${SCALA_IDE_GIT_REPO} ${SCALAIDE_DIR} ${SCALA_IDE_BRANCH}
checkout_git_repo ${SCALARIFORM_GIT_REPO} ${SCALARIFORM_DIR} ${SCALARIFORM_BRANCH}
checkout_git_repo ${SCALA_REFACTORING_GIT_REPO} ${SCALA_REFACTORING_DIR} ${SCALA_REFACTORING_BRANCH}

if $BUILD_PLUGINS
then
    checkout_git_repo ${WORKSHEET_GIT_REPO} ${WORKSHEET_DIR} ${WORKSHEET_BRANCH}
    checkout_git_repo ${TYPESAFE_IDE_GIT_REPO} ${TYPESAFE_IDE_DIR} ${TYPESAFE_IDE_BRANCH}
    assert_typesafe_ide_version_tag_not_empty
fi

build_sbinary
build_sbt
build_toolchain
build_refactoring
build_scalariform
build_ide

if $SIGN_BUILD
then
    sign_ide
fi

if $BUILD_PLUGINS
then
    build_plugins
fi

prepare_nextBase

if [[ -z "$PUBLISH" ]]
then
    debug "Not publishing anything"
else
    case $PUBLISH in

        dev )
    	    publish_nextBase "sdk/next" $ecosystem_platform "dev"
            ;;

        stable )
   	    publish_nextBase "sdk/next" $ecosystem_platform "stable"
            ;;
        *)
            debug "Not publishing base"
    esac
    publish_worksheet "releases" $ecosystem_platform
fi
