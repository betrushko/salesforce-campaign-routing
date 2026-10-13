"""Build deterministic Campaign corrections from Salesforce audit exports.

Inputs are intentionally excluded from Git because they contain operational
record identifiers. Outputs contain Salesforce IDs only and are also excluded
by the repository's CSV ignore rule.
"""

from __future__ import annotations

import csv
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]
RAW_DIR = BASE_DIR / "raw"
OPPORTUNITY_AUDIT = (
    RAW_DIR / "snapshots" / "all_direct_paymenthub_campaign_audit.csv"
)
CAMPAIGN_CATALOG = RAW_DIR / "catalog" / "all_campaigns_catalog.csv"
OPPORTUNITY_UPDATES = (
    RAW_DIR
    / "historical"
    / "historical_opportunity_campaign_updates_nobom.csv"
)
RD_UPDATES = (
    RAW_DIR / "historical" / "historical_rd_campaign_updates_nobom.csv"
)
RD_CONFLICTS = RAW_DIR / "historical" / "historical_rd_campaign_conflicts.csv"
SUMMARY = RAW_DIR / "summaries" / "source_campaign_audit_summary.json"


def normalize(value: str | None) -> str:
    return re.sub(r"\s+", " ", (value or "").strip()).casefold()


def read_csv(path: Path) -> list[dict[str, str]]:
    prefix = path.read_bytes()[:2]
    encoding = "utf-16" if prefix in {b"\xff\xfe", b"\xfe\xff"} else "utf-8-sig"
    with path.open("r", encoding=encoding, newline="") as handle:
        return list(csv.DictReader(handle))


def choose_campaign(
    candidates: list[dict[str, str]],
    normalized_origin: str,
    current_campaign_id: str,
) -> str | None:
    if len(candidates) == 1:
        return candidates[0]["Id"]

    exact_code_matches = [
        candidate
        for candidate in candidates
        if normalize(candidate.get("Campaign_Code__c")) == normalized_origin
    ]
    if len(exact_code_matches) == 1:
        return exact_code_matches[0]["Id"]

    current_matches = [
        candidate
        for candidate in candidates
        if candidate["Id"] == current_campaign_id
    ]
    if len(current_matches) == 1:
        return current_matches[0]["Id"]

    active_matches = [
        candidate
        for candidate in candidates
        if normalize(candidate.get("IsActive")) == "true"
    ]
    if len(active_matches) == 1:
        return active_matches[0]["Id"]
    return None


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    opportunities = read_csv(OPPORTUNITY_AUDIT)
    campaigns = read_csv(CAMPAIGN_CATALOG)

    campaigns_by_name: dict[str, list[dict[str, str]]] = defaultdict(list)
    for campaign in campaigns:
        campaigns_by_name[normalize(campaign["Name"])].append(campaign)

    opportunity_updates: list[dict[str, str]] = []
    unresolved: list[str] = []
    unresolved_origins: Counter[str] = Counter()
    origin_empty = 0
    origin_not_in_name = 0
    origin_not_in_name_updates = 0
    rd_targets: dict[str, set[str]] = defaultdict(set)
    rd_current_campaigns: dict[str, set[str]] = defaultdict(set)

    for opportunity in opportunities:
        origin = opportunity.get("Campa_a_de_origen__c", "")
        normalized_origin = normalize(origin)
        if not normalized_origin:
            origin_empty += 1
            continue

        name_contains_origin = normalized_origin in normalize(opportunity.get("Name"))
        if not name_contains_origin:
            origin_not_in_name += 1

        target_campaign_id = choose_campaign(
            campaigns_by_name.get(normalized_origin, []),
            normalized_origin,
            opportunity.get("CampaignId", ""),
        )
        if not target_campaign_id:
            unresolved.append(opportunity["Id"])
            unresolved_origins[origin] += 1
            continue

        if opportunity.get("CampaignId") != target_campaign_id:
            opportunity_updates.append(
                {"Id": opportunity["Id"], "CampaignId": target_campaign_id}
            )
            if not name_contains_origin:
                origin_not_in_name_updates += 1

        rd_id = opportunity.get("npe03__Recurring_Donation__c", "")
        if rd_id:
            rd_targets[rd_id].add(target_campaign_id)
            current_rd_campaign = opportunity.get(
                "npe03__Recurring_Donation__r.npe03__Recurring_Donation_Campaign__c",
                "",
            )
            if current_rd_campaign:
                rd_current_campaigns[rd_id].add(current_rd_campaign)

    rd_updates: list[dict[str, str]] = []
    rd_conflicts: list[dict[str, str]] = []
    for rd_id, targets in sorted(rd_targets.items()):
        if len(targets) != 1:
            rd_conflicts.append(
                {
                    "Id": rd_id,
                    "TargetCampaignIds": ";".join(sorted(targets)),
                }
            )
            continue
        target = next(iter(targets))
        if rd_current_campaigns.get(rd_id, set()) != {target}:
            rd_updates.append(
                {
                    "Id": rd_id,
                    "npe03__Recurring_Donation_Campaign__c": target,
                }
            )

    write_csv(OPPORTUNITY_UPDATES, ["Id", "CampaignId"], opportunity_updates)
    write_csv(
        RD_UPDATES,
        ["Id", "npe03__Recurring_Donation_Campaign__c"],
        rd_updates,
    )
    write_csv(RD_CONFLICTS, ["Id", "TargetCampaignIds"], rd_conflicts)

    summary = {
        "direct_paymenthub_opportunities": len(opportunities),
        "source_campaign_empty": origin_empty,
        "source_campaign_present": len(opportunities) - origin_empty,
        "source_campaign_not_in_opportunity_name": origin_not_in_name,
        "source_campaign_not_in_name_requiring_update": origin_not_in_name_updates,
        "opportunity_campaign_updates": len(opportunity_updates),
        "unresolved_opportunities": len(unresolved),
        "unresolved_source_campaigns": dict(
            unresolved_origins.most_common()
        ),
        "recurring_donation_updates": len(rd_updates),
        "recurring_donation_conflicts": len(rd_conflicts),
    }
    SUMMARY.parent.mkdir(parents=True, exist_ok=True)
    SUMMARY.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
