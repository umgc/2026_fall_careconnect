#!/usr/bin/env bash
# Runs the actual mapper and test sources without Spring, secrets, or a database.
set -euo pipefail
core_dir="$(cd "$(dirname "$0")/.." && pwd)"
: "${JUNIT_CONSOLE_JAR:?Set JUNIT_CONSOLE_JAR to junit-platform-console-standalone 1.12.1}"
maven_repo="${MAVEN_REPO:-$HOME/.m2/repository}"
jackson_version=2.18.3
classpath="$JUNIT_CONSOLE_JAR"
for artifact in jackson-annotations jackson-core jackson-databind; do
  jar="$maven_repo/com/fasterxml/jackson/core/$artifact/$jackson_version/$artifact-$jackson_version.jar"
  test -f "$jar" || { echo "Missing dependency: $jar" >&2; exit 1; }
  classpath="$classpath:$jar"
done
java_bin="${JAVA_HOME:+$JAVA_HOME/bin/}"
output_dir="$core_dir/target/cerner-mapping-tests"
mkdir -p "$output_dir/classes" "$output_dir/reports"
"${java_bin}javac" --release 17 -cp "$classpath" -d "$output_dir/classes" \
  "$core_dir/src/main/java/com/careconnect/service/cerner/CernerResourceMapper.java" \
  "$core_dir/src/test/java/com/careconnect/service/cerner/CernerResourceMapperTest.java"
"${java_bin}java" -jar "$JUNIT_CONSOLE_JAR" execute \
  --class-path "$output_dir/classes:$classpath" \
  --select-class com.careconnect.service.cerner.CernerResourceMapperTest \
  --reports-dir "$output_dir/reports" --fail-if-no-tests --disable-ansi-colors
