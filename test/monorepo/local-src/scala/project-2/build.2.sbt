name := "test-sbt"

version := "2.3.0-pre.0"

scalaVersion := "2.12.4"

organization := "com.northscaler"

libraryDependencies += "org.apache.spark" %% "spark-sql" % "3.1.1" % "provided"
libraryDependencies += "org.apache.spark" %% "spark-streaming" % "3.1.1" % "provided"
libraryDependencies += "org.apache.spark" %% "spark-streaming-kafka-0-10" % "3.1.1" % "provided"
