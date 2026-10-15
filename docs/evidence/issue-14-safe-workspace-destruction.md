# Issue #14 safe-workspace-destruction evidence

Verification date: 2026-10-15

This public record contains only redacted resource names, plan properties, and
verification results. It excludes account identifiers, addresses, credentials,
private state values, saved-plan contents, repository contents, and T3 data.

## Scope and human boundary

- Tracking issue: [#14](https://github.com/ahammednibras8/rivet/issues/14)
- Dependency Issue #13 was complete before preparation began.
- All tests requiring the original workspace were complete.
- A human reviewed and approved the exact plan before execution.
- The final command required the operator to type the complete names of the
  selected instance, static IP, key pair, and budget.

The final saved plan used OpenTofu 1.13.1 and contained exactly six actions:

```text
aws_budgets_budget.workspace                                 delete
aws_lightsail_instance.workspace                            delete
aws_lightsail_instance_public_ports.workspace               delete
aws_lightsail_key_pair.operator                             delete
aws_lightsail_static_ip.workspace                           delete
aws_lightsail_static_ip_attachment.workspace                delete
```

There were no create, update, replace, or additional delete actions. The plan
digest reviewed immediately before execution was:

```text
1403a2d44c23038bd98158f75c9114c2c0ed0dd1a9419d04d3da001312da5ce3
```

An intentionally incorrect typed confirmation was rejected while all six
resources remained in state. The reviewed confirmation then permitted only the
saved plan.

## Recovery point and canary

Before planning, the workspace was stopped gracefully and one 80 GiB manual
snapshot was created. AWS reported it `available` with the required
`ManagedBy=Rivet`, `Project=Rivet`, `Purpose=RetainedBackup`, and
`Workspace=primary` tags. The source restarted successfully before planning.

The unrelated canary was stored under the protected S3 backend with AES256
encryption and three exact tags. The initial preparation attempt exposed a
missing version-read permission before any Lightsail operation. The host
remained running and no snapshot existed. The temporary policy was corrected
to add only `s3:GetObjectVersion` and `s3:GetObjectVersionTagging`; focused
tests passed before retrying. Failed-attempt evidence and the first versioned
canary object were retained rather than silently deleted.

## Automated post-destruction result

The read-only verifier reported:

```json
{
  "selectedResourcesAbsent": true,
  "state": {
    "retained": true,
    "empty": true,
    "serial": 14,
    "versioning": "Enabled",
    "encryption": "AES256"
  },
  "retainedSnapshot": {
    "state": "available",
    "monthlyUpperBoundUsd": 4
  },
  "canary": {
    "metadataUnchanged": true,
    "contentUnchanged": true,
    "tagsUnchanged": true
  },
  "continuingMonthlyCostUpperBoundUsd": 4
}
```

The instance, public-port policy, static-IP attachment, static IP, key pair,
and budget were absent. OpenTofu retained the original state lineage with an
empty resource set and a newer serial. The canary contents, current version,
ETag, encryption, and tags remained unchanged. The retained manual snapshot
remained available. The state bucket remained versioned and encrypted.

## Permission cleanup and continuing cost

The temporary `rivet-workspace-destroy` inline policy was revoked after
verification. A root-side inventory query confirmed it was absent. The normal
operator role, developer login, protected backend, state history, canary, and
retained snapshot remain.

The only material continuing compute-storage cost from the destroyed
workspace is the retained snapshot, with a conservative USD 4 monthly ceiling.
Small S3 charges continue for the versioned state and canary objects. There is
no running Lightsail instance, allocated static IP, or Rivet budget resource.

T3 and mobile access are intentionally offline after destruction. Restoring
the same threads, credentials, repositories, and T3 Connect identity requires
creating a replacement from the retained snapshot and following the documented
backup-restoration procedure.
