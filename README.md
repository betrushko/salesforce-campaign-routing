# Salesforce campaign routing

Campaign matching and assignment using source attribution, deterministic ambiguity handling, an invocable Apex service and Flow integration.

**Stack:** Apex, Salesforce Flow, Python.

## What this demonstrates

Reusable implementation patterns for data integration, validation and maintainable automation. This is a curated, generalized portfolio edition. It contains no production exports, deployment history, internal access inventory or credentials. API names and source labels have been generalized where needed; configure the matching schema in your own sandbox before use.

## Getting started

For Salesforce work, use Salesforce CLI and a dedicated sandbox with the required schema and NPSP dependencies. Inspect `manifest/package.xml`, then validate with `sf project deploy start --dry-run --manifest manifest/package.xml --target-org DEMO_SANDBOX`. This repository has not been deployed or tested against a live org during portfolio preparation. 

## Source map

- `README.md`
- `force-app/main/default/classes/PaymentHubCampaignAssignment.cls`
- `force-app/main/default/classes/PaymentHubCampaignAssignment.cls-meta.xml`
- `force-app/main/default/classes/PaymentHubCampaignAssignmentTest.cls`
- `force-app/main/default/classes/PaymentHubCampaignAssignmentTest.cls-meta.xml`
- `force-app/main/default/flows/PaymentHub_Assign_Specific_Campaign.flow-meta.xml`
- `manifest/package.xml`
- `queries/direct_paymenthub_with_rd_source.soql`
- `scripts/build_source_campaign_updates.py`
- `sfdx-project.json`

## Validation

Python sources and JSON/XML configuration are checked locally. Apex test classes are retained where present; executing them requires a compatible sandbox. No Salesforce query, deployment, backfill or record mutation was performed during preparation. See [SECURITY.md](SECURITY.md) for data handling.
