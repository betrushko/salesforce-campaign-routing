public without sharing class PaymentHubCampaignAssignment {
    public class Request {
        @InvocableVariable(required=true)
        public Id opportunityId;
    }

    public class Result {
        @InvocableVariable
        public Id opportunityId;
        @InvocableVariable
        public Id campaignId;
        @InvocableVariable
        public String message;
    }

    @InvocableMethod(
        label='Assign PaymentHub source Campaign'
        description='Assigns the Opportunity and related Recurring Donation by matching each record source Campaign exactly.'
    )
    public static List<Result> assignFromPaymentHubName(List<Request> requests) {
        Set<Id> opportunityIds = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.opportunityId != null) {
                opportunityIds.add(request.opportunityId);
            }
        }

        List<Opportunity> opportunities = [
            SELECT Id, Campa_a_de_origen__c, CampaignId,
                   npe03__Recurring_Donation__c,
                   npe03__Recurring_Donation__r.Campa_a_de_origen__c,
                   npe03__Recurring_Donation__r.npe03__Recurring_Donation_Campaign__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];
        List<Campaign> campaigns = [
            SELECT Id, Name, Campaign_Code__c, IsActive, CreatedDate
            FROM Campaign
            WHERE Name != null
        ];

        Map<String, List<Campaign>> campaignsByNormalizedName =
            indexCampaignsByNormalizedName(campaigns);
        Map<Id, Id> matches = resolveCampaignsByOrigin(
            opportunities,
            campaignsByNormalizedName
        );
        List<Opportunity> opportunityUpdates = new List<Opportunity>();
        Map<Id, npe03__Recurring_Donation__c> recurringDonationUpdates =
            new Map<Id, npe03__Recurring_Donation__c>();

        for (Opportunity opportunity : opportunities) {
            Id campaignId = matches.get(opportunity.Id);
            if (campaignId != null && opportunity.CampaignId != campaignId) {
                opportunityUpdates.add(new Opportunity(
                    Id = opportunity.Id,
                    CampaignId = campaignId
                ));
            }
            if (opportunity.npe03__Recurring_Donation__c == null) {
                continue;
            }

            String recurringDonationOrigin =
                opportunity.npe03__Recurring_Donation__r.Campa_a_de_origen__c;
            Id recurringDonationCampaignId = String.isBlank(recurringDonationOrigin)
                ? campaignId
                : resolveCampaignByOrigin(
                    recurringDonationOrigin,
                    opportunity.npe03__Recurring_Donation__r.npe03__Recurring_Donation_Campaign__c,
                    campaignsByNormalizedName
                );
            if (recurringDonationCampaignId != null
                && opportunity.npe03__Recurring_Donation__r.npe03__Recurring_Donation_Campaign__c
                    != recurringDonationCampaignId) {
                recurringDonationUpdates.put(
                    opportunity.npe03__Recurring_Donation__c,
                    new npe03__Recurring_Donation__c(
                        Id = opportunity.npe03__Recurring_Donation__c,
                        npe03__Recurring_Donation_Campaign__c =
                            recurringDonationCampaignId
                    )
                );
            }
        }

        if (!opportunityUpdates.isEmpty()) {
            update opportunityUpdates;
        }
        if (!recurringDonationUpdates.isEmpty()) {
            update recurringDonationUpdates.values();
        }

        List<Result> results = new List<Result>();
        for (Request request : requests) {
            Result result = new Result();
            result.opportunityId = request == null ? null : request.opportunityId;
            result.campaignId = result.opportunityId == null ? null : matches.get(result.opportunityId);
            result.message = result.campaignId == null
                ? 'No unique Campaign was found for the PaymentHub source Campaign value.'
                : 'Opportunity Campaign assigned; the related Recurring Donation was evaluated from its own source Campaign when available.';
            results.add(result);
        }
        return results;
    }

    @TestVisible
    private static Map<Id, Id> resolveCampaignsByOrigin(
        List<Opportunity> opportunities,
        List<Campaign> campaigns
    ) {
        return resolveCampaignsByOrigin(
            opportunities,
            indexCampaignsByNormalizedName(campaigns)
        );
    }

    private static Map<Id, Id> resolveCampaignsByOrigin(
        List<Opportunity> opportunities,
        Map<String, List<Campaign>> campaignsByNormalizedName
    ) {
        Map<Id, Id> matches = new Map<Id, Id>();
        for (Opportunity opportunity : opportunities) {
            Id campaignId = resolveCampaignByOrigin(
                opportunity.Campa_a_de_origen__c,
                opportunity.CampaignId,
                campaignsByNormalizedName
            );
            if (campaignId != null) {
                matches.put(opportunity.Id, campaignId);
            }
        }
        return matches;
    }

    private static Map<String, List<Campaign>> indexCampaignsByNormalizedName(
        List<Campaign> campaigns
    ) {
        Map<String, List<Campaign>> campaignsByNormalizedName =
            new Map<String, List<Campaign>>();
        for (Campaign campaign : campaigns) {
            String normalizedName = normalize(campaign.Name);
            if (String.isBlank(normalizedName)) {
                continue;
            }
            if (!campaignsByNormalizedName.containsKey(normalizedName)) {
                campaignsByNormalizedName.put(normalizedName, new List<Campaign>());
            }
            campaignsByNormalizedName.get(normalizedName).add(campaign);
        }
        return campaignsByNormalizedName;
    }

    private static Id resolveCampaignByOrigin(
        String sourceCampaign,
        Id currentCampaignId,
        Map<String, List<Campaign>> campaignsByNormalizedName
    ) {
        String normalizedOrigin = normalize(sourceCampaign);
        if (String.isBlank(normalizedOrigin)
            || !campaignsByNormalizedName.containsKey(normalizedOrigin)) {
            return null;
        }
        return chooseCanonicalCampaign(
            campaignsByNormalizedName.get(normalizedOrigin),
            normalizedOrigin,
            currentCampaignId
        );
    }

    private static Id chooseCanonicalCampaign(
        List<Campaign> candidates,
        String normalizedOrigin,
        Id currentCampaignId
    ) {
        if (candidates.size() == 1) {
            return candidates[0].Id;
        }

        List<Campaign> exactCodeMatches = new List<Campaign>();
        for (Campaign candidate : candidates) {
            if (normalize(candidate.Campaign_Code__c) == normalizedOrigin) {
                exactCodeMatches.add(candidate);
            }
        }
        if (exactCodeMatches.size() == 1) {
            return exactCodeMatches[0].Id;
        }

        // Preserve an already correct same-name Campaign when duplicate
        // Campaign records exist and no unique external code resolves them.
        for (Campaign candidate : candidates) {
            if (candidate.Id == currentCampaignId) {
                return currentCampaignId;
            }
        }

        List<Campaign> activeCandidates = new List<Campaign>();
        for (Campaign candidate : candidates) {
            if (candidate.IsActive) {
                activeCandidates.add(candidate);
            }
        }
        return activeCandidates.size() == 1 ? activeCandidates[0].Id : null;
    }

    private static String normalize(String value) {
        return String.isBlank(value)
            ? ''
            : value.trim().replaceAll('\\s+', ' ').toLowerCase();
    }
}
