#!/usr/bin/env bash

ensure_state_bucket() {
  local bucket="$1"
  local expected_owner="$2"
  local region="$3"
  local actual_region

  if aws s3api head-bucket \
    --bucket "$bucket" \
    --expected-bucket-owner "$expected_owner" \
    --region "$region" 2>/dev/null; then
    printf 'State bucket already exists.\n'
  else
    aws s3api create-bucket \
      --bucket "$bucket" \
      --bucket-namespace account-regional \
      --object-ownership BucketOwnerEnforced \
      --create-bucket-configuration "LocationConstraint=${region}" \
      --region "$region" \
      >/dev/null || return $?

    printf 'State bucket created.\n'
  fi

  actual_region="$(
    aws s3api get-bucket-location \
      --bucket "$bucket" \
      --expected-bucket-owner "$expected_owner" \
      --region "$region" \
      --query LocationConstraint \
      --output text
  )" || return $?

  if [[ "$actual_region" != "$region" ]]; then
    printf 'error: state bucket exists in unexpected region %s\n' \
      "$actual_region" >&2
    return 1
  fi

  printf 'State bucket ownership and region verified.\n'
}

configure_state_bucket() {
  local bucket="$1"
  local expected_owner="$2"
  local region="$3"
  local state_object_key="$4"
  local bucket_policy

  aws s3api put-bucket-ownership-controls \
    --bucket "$bucket" \
    --expected-bucket-owner "$expected_owner" \
    --ownership-controls \
      'Rules=[{ObjectOwnership=BucketOwnerEnforced}]' \
    --region "$region" || return $?

  aws s3api put-public-access-block \
    --bucket "$bucket" \
    --expected-bucket-owner "$expected_owner" \
    --public-access-block-configuration \
      'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true' \
    --region "$region" || return $?

  aws s3api put-bucket-encryption \
    --bucket "$bucket" \
    --expected-bucket-owner "$expected_owner" \
    --server-side-encryption-configuration \
      'Rules=[{ApplyServerSideEncryptionByDefault={SSEAlgorithm=AES256}}]' \
    --region "$region" || return $?

  aws s3api put-bucket-versioning \
    --bucket "$bucket" \
    --expected-bucket-owner "$expected_owner" \
    --versioning-configuration 'Status=Enabled' \
    --region "$region" || return $?

  aws s3api put-bucket-tagging \
    --bucket "$bucket" \
    --expected-bucket-owner "$expected_owner" \
    --tagging \
      'TagSet=[{Key=ManagedBy,Value=AWSCLI},{Key=Phase,Value=phase-1},{Key=Project,Value=Rivet}]' \
    --region "$region" || return $?

  aws s3api put-bucket-lifecycle-configuration \
    --bucket "$bucket" \
    --expected-bucket-owner "$expected_owner" \
    --lifecycle-configuration \
      'Rules=[{ID=LimitNoncurrentStateAndLockVersions,Status=Enabled,Filter={Prefix=phase-1/},NoncurrentVersionExpiration={NoncurrentDays=90,NewerNoncurrentVersions=10},Expiration={ExpiredObjectDeleteMarker=true}}]' \
    --region "$region" || return $?

  bucket_policy="$(render_state_bucket_policy "$bucket" "$state_object_key")" || return $?

  aws s3api put-bucket-policy \
    --bucket "$bucket" \
    --expected-bucket-owner "$expected_owner" \
    --policy "$bucket_policy" \
    --region "$region" || return $?

  printf 'State bucket protection settings converged.\n'
}

verify_state_bucket_core_controls() {
  local bucket="$1"
  local expected_owner="$2"
  local region="$3"
  local ownership
  local public_access
  local encryption
  local versioning

  ownership="$(
    aws s3api get-bucket-ownership-controls \
      --bucket "$bucket" \
      --expected-bucket-owner "$expected_owner" \
      --region "$region" \
      --query 'OwnershipControls.Rules[0].ObjectOwnership' \
      --output text
  )" || return $?

  public_access="$(
    aws s3api get-public-access-block \
      --bucket "$bucket" \
      --expected-bucket-owner "$expected_owner" \
      --region "$region" \
      --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' \
      --output text
  )" || return $?

  encryption="$(
    aws s3api get-bucket-encryption \
      --bucket "$bucket" \
      --expected-bucket-owner "$expected_owner" \
      --region "$region" \
      --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
      --output text
  )" || return $?

  versioning="$(
    aws s3api get-bucket-versioning \
      --bucket "$bucket" \
      --expected-bucket-owner "$expected_owner" \
      --region "$region" \
      --query Status \
      --output text
  )" || return $?

  if [[ "$ownership" != "BucketOwnerEnforced" ]]; then
    printf 'error: bucket ownership control was not retained\n' >&2
    return 1
  fi

  if [[ "$public_access" != $'True\tTrue\tTrue\tTrue' ]]; then
    printf 'error: bucket public-access block is incomplete\n' >&2
    return 1
  fi

  if [[ "$encryption" != "AES256" ]]; then
    printf 'error: bucket default encryption is not SSE-S3\n' >&2
    return 1
  fi

  if [[ "$versioning" != "Enabled" ]]; then
    printf 'error: bucket versioning is not enabled\n' >&2
    return 1
  fi

  printf 'State bucket core protection settings verified.\n'
}

verify_state_bucket_metadata_controls() {
  local bucket="$1"
  local expected_owner="$2"
  local region="$3"
  local state_object_key="$4"
  local tags
  local lifecycle_matches
  local expected_policy
  local installed_policy
  local expected_policy_canonical
  local installed_policy_canonical

  tags="$(
    aws s3api get-bucket-tagging \
      --bucket "$bucket" \
      --expected-bucket-owner "$expected_owner" \
      --region "$region" \
      --query 'sort_by(TagSet, &Key)[].[Key,Value]' \
      --output text
  )" || return $?

  lifecycle_matches="$(
    # The backticks are JMESPath literals, not shell command substitutions.
    # shellcheck disable=SC2016
    aws s3api get-bucket-lifecycle-configuration \
      --bucket "$bucket" \
      --expected-bucket-owner "$expected_owner" \
      --region "$region" \
      --query 'length(Rules[?ID==`LimitNoncurrentStateAndLockVersions` && Status==`Enabled` && Filter.Prefix==`phase-1/` && NoncurrentVersionExpiration.NoncurrentDays==`90` && NoncurrentVersionExpiration.NewerNoncurrentVersions==`10` && Expiration.ExpiredObjectDeleteMarker==`true`])' \
      --output text
  )" || return $?

  installed_policy="$(
    aws s3api get-bucket-policy \
      --bucket "$bucket" \
      --expected-bucket-owner "$expected_owner" \
      --region "$region" \
      --query Policy \
      --output text
  )" || return $?

  expected_policy="$(
    render_state_bucket_policy "$bucket" "$state_object_key"
  )" || return $?

  expected_policy_canonical="$(
    printf '%s' "$expected_policy" | jq --sort-keys --compact-output .
  )" || return $?

  installed_policy_canonical="$(
    printf '%s' "$installed_policy" | jq --sort-keys --compact-output .
  )" || return $?

  if [[ "$tags" != $'ManagedBy\tAWSCLI\nPhase\tphase-1\nProject\tRivet' ]]; then
    printf 'error: state bucket tags do not match the required set\n' >&2
    return 1
  fi

  if [[ "$lifecycle_matches" != "1" ]]; then
    printf 'error: state bucket lifecycle retention is incorrect\n' >&2
    return 1
  fi

  if [[ "$installed_policy_canonical" != "$expected_policy_canonical" ]]; then
    printf 'error: installed state bucket policy differs from the required policy\n' >&2
    return 1
  fi

  printf 'State bucket tags, retention, and policy verified.\n'
}
