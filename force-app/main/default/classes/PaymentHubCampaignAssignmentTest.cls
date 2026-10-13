@IsTest
private class PaymentHubCampaignAssignmentTest {
    @IsTest
    static void invocableAssignsCampaignOnInsertedPaymentHubOpportunity() {
        Campaign parentCampaign = new Campaign(
            Name = 'TEST-FH-BASE',
            IsActive = true,
            StartDate = Date.today()
        );
        Campaign exactCampaign = new Campaign(
            Name = 'TEST-FH-BASE/OO/EM',
            IsActive = true,
            StartDate = Date.today()
        );
        insert new List<Campaign>{ parentCampaign, exactCampaign };

        Opportunity opportunity = new Opportunity(
            Name = 'Persona 23/07/2026',
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            LeadSource = 'PaymentHub',
            Auth__c = 'DEMO-FH-TEST-CAMPAIGN-001',
            Campa_a_de_origen__c = 'TEST-FH-BASE/OO/EM',
            CampaignId = parentCampaign.Id
        );
        insert opportunity;

        PaymentHubCampaignAssignment.Request request =
            new PaymentHubCampaignAssignment.Request();
        request.opportunityId = opportunity.Id;

        Test.startTest();
        List<PaymentHubCampaignAssignment.Result> results =
            PaymentHubCampaignAssignment.assignFromPaymentHubName(
                new List<PaymentHubCampaignAssignment.Request>{ request }
            );
        Test.stopTest();

        Opportunity refreshed = [
            SELECT CampaignId
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];
        System.assertEquals(exactCampaign.Id, refreshed.CampaignId);
        System.assertEquals(exactCampaign.Id, results[0].campaignId);
    }

    @IsTest
    static void recurringDonationUsesItsOwnSourceCampaign() {
        Campaign opportunityCampaign = new Campaign(
            Name = 'TEST-FH-OPPORTUNITY-SOURCE',
            IsActive = true,
            StartDate = Date.today()
        );
        Campaign recurringDonationCampaign = new Campaign(
            Name = 'TEST-FH-RD-SOURCE',
            IsActive = true,
            StartDate = Date.today()
        );
        insert new List<Campaign>{
            opportunityCampaign,
            recurringDonationCampaign
        };

        Account account = new Account(Name = 'PaymentHub Campaign Test Account');
        insert account;
        Contact contact = new Contact(
            LastName = 'PaymentHub Campaign Test Contact',
            AccountId = account.Id
        );
        insert contact;
        npe03__Recurring_Donation__c recurringDonation =
            new npe03__Recurring_Donation__c(
                Name = 'PaymentHub Campaign Test RD',
                npe03__Contact__c = contact.Id,
                npe03__Amount__c = 100,
                npe03__Date_Established__c = Date.today(),
                npe03__Installment_Period__c = 'Monthly',
                npe03__Schedule_Type__c = 'Multiply By',
                npe03__Open_Ended_Status__c = 'Open',
                Campa_a_de_origen__c = 'TEST-FH-RD-SOURCE',
                npe03__Recurring_Donation_Campaign__c =
                    opportunityCampaign.Id
            );
        insert recurringDonation;

        Opportunity opportunity = new Opportunity(
            Name = 'PaymentHub Campaign independent RD source',
            AccountId = account.Id,
            ContactId = contact.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Amount = 100,
            LeadSource = 'PaymentHub',
            Auth__c = 'DEMO-FH-TEST-CAMPAIGN-002',
            Campa_a_de_origen__c = 'TEST-FH-OPPORTUNITY-SOURCE',
            CampaignId = recurringDonationCampaign.Id,
            npe03__Recurring_Donation__c = recurringDonation.Id
        );
        insert opportunity;

        PaymentHubCampaignAssignment.Request request =
            new PaymentHubCampaignAssignment.Request();
        request.opportunityId = opportunity.Id;

        Test.startTest();
        PaymentHubCampaignAssignment.assignFromPaymentHubName(
            new List<PaymentHubCampaignAssignment.Request>{ request }
        );
        Test.stopTest();

        Opportunity refreshedOpportunity = [
            SELECT CampaignId
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];
        npe03__Recurring_Donation__c refreshedRecurringDonation = [
            SELECT npe03__Recurring_Donation_Campaign__c
            FROM npe03__Recurring_Donation__c
            WHERE Id = :recurringDonation.Id
        ];
        System.assertEquals(
            opportunityCampaign.Id,
            refreshedOpportunity.CampaignId
        );
        System.assertEquals(
            recurringDonationCampaign.Id,
            refreshedRecurringDonation.npe03__Recurring_Donation_Campaign__c
        );
    }

    @IsTest
    static void usesSourceCampaignEvenWhenItIsAbsentFromOpportunityName() {
        Opportunity opportunity = new Opportunity(
            Id = '006000000000001AAA',
            Name = 'Donor 02/07/2026',
            Campa_a_de_origen__c = 'MXES01EY00 General Emergencies/OO/EM'
        );
        Campaign parentCampaign = new Campaign(
            Id = '701000000000001AAA',
            Name = 'MXES01EY00 General Emergencies'
        );
        Campaign exactCampaign = new Campaign(
            Id = '701000000000002AAA',
            Name = 'MXES01EY00 General Emergencies/OO/EM'
        );

        Map<Id, Id> matches = PaymentHubCampaignAssignment.resolveCampaignsByOrigin(
            new List<Opportunity>{ opportunity },
            new List<Campaign>{ parentCampaign, exactCampaign }
        );

        System.assertEquals(exactCampaign.Id, matches.get(opportunity.Id));
    }

    @IsTest
    static void isCaseAndWhitespaceInsensitive() {
        Opportunity opportunity = new Opportunity(
            Id = '006000000000003AAA',
            Name = 'Donor without Campaign text',
            Campa_a_de_origen__c = 'MXES01EY00   GENERAL EMERGENCIES/OO/EM'
        );
        Campaign exactCampaign = new Campaign(
            Id = '701000000000004AAA',
            Name = 'MXES01EY00 General Emergencies/OO/EM'
        );

        Map<Id, Id> matches = PaymentHubCampaignAssignment.resolveCampaignsByOrigin(
            new List<Opportunity>{ opportunity },
            new List<Campaign>{ exactCampaign }
        );

        System.assertEquals(exactCampaign.Id, matches.get(opportunity.Id));
    }

    @IsTest
    static void usesExactCampaignCodeToResolveDuplicateNames() {
        Opportunity opportunity = new Opportunity(
            Id = '006000000000005AAA',
            Name = 'Donor without Campaign text',
            Campa_a_de_origen__c = 'MXES01EY00 General Emergencies/OO/EM'
        );
        Campaign duplicateOne = new Campaign(
            Id = '701000000000006AAA',
            Name = 'MXES01EY00 General Emergencies/OO/EM',
            Campaign_Code__c = 'MXES01EY00 General Emergencies/OO/EM'
        );
        Campaign duplicateTwo = new Campaign(
            Id = '701000000000007AAA',
            Name = 'MXES01EY00 General Emergencies/OO/EM'
        );

        Map<Id, Id> matches = PaymentHubCampaignAssignment.resolveCampaignsByOrigin(
            new List<Opportunity>{ opportunity },
            new List<Campaign>{ duplicateOne, duplicateTwo }
        );

        System.assertEquals(duplicateOne.Id, matches.get(opportunity.Id));
    }

    @IsTest
    static void ignoresOnlyBlankSourceCampaignValues() {
        Opportunity opportunity = new Opportunity(
            Id = '006000000000008AAA',
            Name = 'Donor MXES01EY00 General Emergencies/OO/EM'
        );
        Campaign campaign = new Campaign(
            Id = '701000000000009AAA',
            Name = 'MXES01EY00 General Emergencies/OO/EM'
        );

        Map<Id, Id> matches = PaymentHubCampaignAssignment.resolveCampaignsByOrigin(
            new List<Opportunity>{ opportunity },
            new List<Campaign>{ campaign }
        );

        System.assertEquals(false, matches.containsKey(opportunity.Id));
    }
}
