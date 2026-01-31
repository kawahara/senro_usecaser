# Steepfile for SenroUsecaser

target :lib do
  signature "sig/generated"
  signature "sig/overrides.rbs"

  check "lib"

  # Standard library
  library "time"
end

target :examples do
  signature "sig/generated"
  signature "sig/overrides.rbs"
  signature "examples/sig"

  check "examples"

  # Standard library
  library "time"
end
