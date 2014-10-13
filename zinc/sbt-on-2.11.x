# This is the dbuild configuration to build zinc and its dependencies on Scala 2.11.x
#  It is run through the Scala IDE parametrized job: https://jenkins.scala-ide.org:8496/jenkins/job/parameterized-zinc/ 
#  and other uber-build runs.

# There should not be any need to change this file. Except to change the base repositories, most parameters can be modified
# at the uber-build configuration level (check the sbt-publish configuration for examples) or by tweaking the properties file
# (check stepZinc inside the uber-build script).

# This file knows how to build sbt inside Ivy and publish *maven nightly artifacts* for consumption.
# Combined, we run tests to ensure that sanity exists for these artifacts (specifically, does Zinc build/run).
# This build is *tied* to the 2.11.x scala series.  Scala's modularization requires different build files for
# both 2.10.x and 2.11.x series.  The main difference is in how modules are grabbed.
# The four projects that are sbt related are:
#
# - harrah/sbinary     * Dependency required for building sbt/sbt
# - sbt/sbt            * Build/Test/Deploys via Ivy
# - sbt/sbt-republish  * Actually releases maven artifacts
# - typesafehub/zinc   * for testing only


# If you'd like to create a "branch release" of this build, here's what you need to do:
# - Copy the sbt-on-2.11.x.properties file to a new name.
# - Override the variables in there for your purposes.
# - Create a new jenkins job where the environment variable SBT_TAG_PROPS points at your properties file.
# - Test locally with the command `SBT_VERSION_PROPERTIES_FILE=file:my.properties ./bin/dbuild sbt-on-2.11.x`
{
  properties: [
    "file:sbt-on-2.11.x.properties"
    ${?SBT_VERSION_PROPERTIES_FILE}  # If a properties environment vairable exists, we load it
    ${?DBUILD_LOCAL_PROPERTIES} # If a local properties file is defined, we load it
    "file:versions.properties"
  ]
  // Variables that may be external.  We have the defaults here.
  vars: {
    scala_branch: "2.11"
    scala_branch: ${?SCALA_BRANCH}
    scala-version: ${?SCALA_VERSION}
    publish-repo: ${?PUBLISH_REPO}
    sbt-version: ${?SBT_VERSION}
    sbt-tag: ${?SBT_TAG}
    sbt.snapshot.suffix: ${?SBT_SNAPSHOT_SUFFIX}
  }
  build: {
    "projects":[
      {
        system: assemble
        name:   scala2
        deps.ignore: "org.scalacheck#scalacheck"
        extra.parts: {
          cross-version: standard
          sbt-version: "0.13.5"
        }
        # TODO - We want the scala version used to be 
        #        given to use from the IDE build, if we can.
        extra.parts.projects: [
          {
            name:  "scala-lib",
            system: "ivy",
            set-version: ${vars.scala-version}
            uri:    "ivy:org.scala-lang#scala-library;"${vars.maven.version.number}
          }, {
            name:  "scala-reflect",
            system: "ivy",
            uri:    "ivy:org.scala-lang#scala-reflect;"${vars.maven.version.number}
            set-version: ${vars.scala-version}
          }, {
            name:  "scala-compiler",
            system: "ivy",
            set-version: ${vars.scala-version}
            uri:    "ivy:org.scala-lang#scala-compiler;"${vars.maven.version.number}
          },
          {
            name:  "scala-xml",
            system: "ivy",
            uri:    "ivy:org.scala-lang.modules#scala-xml_"${vars.scala.binary.version}";"${vars.scala-xml.version.number}
            set-version: ${vars.scala-xml.version.number}// required by sbinary?
          }, {
            name:  "scala-parser-combinators",
            system: "ivy",
            uri:    "ivy:org.scala-lang.modules#scala-parser-combinators_"${vars.scala.binary.version}";"${vars.scala-parser-combinators.version.number},
            set-version: ${vars.scala-parser-combinators.version.number} // required by sbinary?
          }
        ]
      },
      {
        name: scalacheck
        extra.sbt-version: "0.13.5",
        uri: "https://github.com/rickynils/scalacheck.git#"${vars.scalacheck-tag}
      },
      {
        name:   "sbinary",
        extra.sbt-version: "0.13.5",
        uri:    "git://github.com/harrah/sbinary.git#"${vars.sbinary-tag}
      }, {
        name:   "sbt",
        uri:    "git://github.com/sbt/sbt.git#"${vars.sbt-tag}
        extra: {
          sbt-version: ${vars.sbt-build-sbt-version},
          projects: ["compiler-interface",
                     "classpath","logging","io","control","classfile",
                     "process","relation","interface","persist","api",
                     "compiler-integration","incremental-compiler","compile","launcher-interface"
                    ],
          run-tests: false,
          commands: [ "set every Util.includeTestDependencies := false" // Without this, we have to build specs2
                    ]
        }
      }, {
        name:   "sbt-republish",
        uri:    "http://github.com/typesafehub/sbt-republish.git#"${vars.sbt-republish-tag},
        set-version: ${vars.sbt-version}
      }, {
        name:   "zinc",
        uri:    "https://github.com/typesafehub/zinc.git#"${vars.zinc-tag}
      }
    ],
    cross-version:standard,
  }
  options: {
    deploy: [
      {
        uri=${?vars.publish-repo},
        credentials=${HOME}"/.credentials",
        projects:["sbt-republish"]
      }
    ]
    notifications: {
      send:[{
        projects: "."
        send.to: "qbranch@typesafe.com"
        when: bad
      },{
        projects: "."
        kind: console
        when: always
      }]
      default.send: {
        from: "jenkins-dbuild <antonio.cunei@typesafe.com>"
        smtp:{
          server: "psemail.epfl.ch"
          encryption: none
        }
      }
    }
  }
  options.resolvers: ${?vars.resolvers}
}

// {
//   name:  "scala-compiler-doc",
//   system: "ivy",
//   set-version: ${vars.scala-compiler-doc.version.number}
//   uri:    "ivy:org.scala-lang.modules#scala-compiler-doc_"${vars.scala.binary.version}";"${vars.scala-compiler-doc.version.number}
// }, {
//   name:  "scala-compiler-interactive",
//   system: "ivy",
//   set-version: ${vars.scala-compiler-interactive.version.number}
//   uri:    "ivy:org.scala-lang.modules#scala-compiler-interactive_"${vars.scala.binary.version}";"${vars.scala-compiler-interactive.version.number}
// },
