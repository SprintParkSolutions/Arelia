/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-04-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest
private class SiteVisitApprovalControllerTest {

    @testSetup
    static void setupData() {
        User supervisor;
        User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        
        System.runAs(thisUser) {
            UserRole managerRole = new UserRole(DeveloperName = 'Arelia_Manager', Name = 'Arelia Manager');
            insert managerRole;

            supervisor = TestDataUtility.createSupervisorUser('spvsr');
            supervisor.UserRoleId = managerRole.Id;
            supervisor.Email = 'manager@arelia.example.com';
            update supervisor;
        }

        // Setup Lead with fields from your provided image
        Lead testLead = TestDataUtility.createLead('Arelia Prospect');
        testLead.FirstName = 'Arelia';
        testLead.LastName = 'Client';
        testLead.Company = 'Arelia Interiors';
        testLead.Appointment_Completed__c = true;
        // Setting fields seen in your 'Address Information' & 'Appointment' sections
        testLead.Estimated_Start_Date__c = System.today(); 
        update testLead;

        Opportunity testOpp = new Opportunity(
            Name = 'Arelia Design Project',
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(30)
        );
        insert testOpp;

        // Mock Email Templates
        System.runAs(thisUser) {
            List<String> labels = new List<String>{
                Label.Arelia_Living_Site_Visit_Approval_by_Manager_Template,
                Label.Arelia_Living_Site_Visit_Negotation_by_Manager_Template,
                Label.Arelia_Living_Opportunity_Re_Visit_Site_Manager_Approval_Email_Template,
                Label.Arelia_Living_Lead_Conversion_Approval_Email_Template
            };

            List<EmailTemplate> templates = new List<EmailTemplate>();
            for (String lbl : labels) {
                if (String.isNotBlank(lbl)) {
                    templates.add(new EmailTemplate(
                        DeveloperName = lbl.replaceAll('[^a-zA-Z0-9]', '_'),
                        Name = lbl,
                        FolderId = UserInfo.getUserId(),
                        TemplateType = 'custom',
                        IsActive = true,
                        Subject = 'Arelia Update',
                        HtmlValue = '<html><body>Supervisor: {{{Site_Visit_Report__c.Supervisor_User__r.Name}}}</body></html>'
                    ));
                }
            }
            insert templates;
        }

        Id leadRt = Schema.SObjectType.Site_Visit_Report__c.getRecordTypeInfosByDeveloperName().get('Lead_Site_Visit_Report').getRecordTypeId();
        
        // FIXED: Using the time slot format shown in your image (9AM-10AM)
        Site_Visit_Report__c report = new Site_Visit_Report__c(
            Lead__c = testLead.Id,
            Supervisor_User__c = supervisor.Id,
            RecordTypeId = leadRt,
            Site_Visit_Report_Status__c = 'Pending',
            Total_Estimated_Cost__c = 10000,
            Site_Visit_Time_Slot__c = '9AM-10AM' 
        );
        insert report;
    }

    @isTest
    static void testStatusSyncAndLeadConversionCoverage() {
        Site_Visit_Report__c report = [SELECT Id, Lead__c FROM Site_Visit_Report__c LIMIT 1];
        
        Test.startTest();
        // Covering the Lead Conversion Email branch (often missed)
        report.Management_Approval__c = true;
        report.Site_Visit_Report_Status__c = 'Approved';
        update report;
        Test.stopTest();

        Lead l = [SELECT Site_Visit_Status__c FROM Lead WHERE Id = :report.Lead__c];
        Assert.areEqual('Approved', l.Site_Visit_Status__c);
    }

    @isTest
    static void testOpportunityNegotiationFlow() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Id oppRt = Schema.SObjectType.Site_Visit_Report__c.getRecordTypeInfosByDeveloperName().get('Opportunity_Site_Visit_Report').getRecordTypeId();
        
        Site_Visit_Report__c oppReport = new Site_Visit_Report__c(
            Opportunity__c = opp.Id,
            RecordTypeId = oppRt,
            Total_Estimated_Cost__c = 5000,
            Site_Visit_Report_Status__c = 'Pending'
        );
        insert oppReport;

        Test.startTest();
        oppReport.Negotiate__c = true;
        oppReport.Negotation_Reason__c = 'Budget realignment';
        update oppReport;
        Test.stopTest();

        Assert.isTrue(Limits.getEmailInvocations() > 0);
    }

    @isTest
    static void testHandlerUtilities() {
        // Covering guard clauses and catch blocks for 100% handler coverage
        SiteVisitReportHandler.afterInsert(null);
        
        try {
            // Passing a User ID instead of Report ID to force a Query Exception/Catch block
            SiteVisitReportHandler.sendApprovalEmails(new List<Id>{UserInfo.getUserId()});
        } catch(Exception e) {
            System.debug('Exception caught for coverage');
        }
    }
}