/**
 * @FileName    : AreliaManualProjectRequestControllerTest.cls
 * @description : Test class for Arelia_ManualProjectRequestController.
 *                - Verifies lead retrieval
 *                - Verifies picklist helper methods
 *                - Verifies updateLead happy path and guard rails
 */
@IsTest
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexUnitTestShouldNotUseSeeAllData')
private class AreliaManualProjectRequestControllerTest {

    // ----------------------------------------------------------------------
    // Test data
    // ----------------------------------------------------------------------
    @TestSetup
    static void setupData() {
        Lead l = new Lead(
            FirstName  = 'Test',
            LastName   = 'Lead',
            Company    = 'Test Company',
            Email      = 'test@example.com',
            Phone      = '9999999999',
            Status     = 'Open - Not Contacted',
            Project_Request_Submitted__c = false
        );
        insert l;
    }

    // ----------------------------------------------------------------------
    // getLeadById tests
    // ----------------------------------------------------------------------
    @IsTest
    static void testGetLeadByIdValid() {
        Lead setupLead = [SELECT Id FROM Lead LIMIT 1];

        Test.startTest();
        Lead result = Arelia_ManualProjectRequestController.getLeadById(setupLead.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Expected lead to be returned.');
        System.assertEquals(setupLead.Id, result.Id, 'Returned lead Id should match.');
    }

    @IsTest
    static void testGetLeadByIdNull() {
        Test.startTest();
        Lead result = Arelia_ManualProjectRequestController.getLeadById(null);
        Test.stopTest();

        System.assertEquals(null, result, 'When leadId is null, result should be null.');
    }

    // ----------------------------------------------------------------------
    // Picklist helper tests
    // ----------------------------------------------------------------------
    @IsTest
    static void testGetTypeOfProjectPicklistValues() {
        Test.startTest();
        List<String> values = Arelia_ManualProjectRequestController.getTypeOfProjectPicklistValues();
        Test.stopTest();

        System.assertNotEquals(null, values, 'Picklist values list should not be null.');
    }

    @IsTest
    static void testGetPlanLevelPicklistValues() {
        Test.startTest();
        List<String> values = Arelia_ManualProjectRequestController.getPlanLevelPicklistValues();
        Test.stopTest();

        System.assertNotEquals(null, values, 'Plan level picklist values should not be null.');
    }

    // ----------------------------------------------------------------------
    // updateLead – payload guard tests
    // ----------------------------------------------------------------------
    @IsTest
    static void testUpdateLeadNullPayloadAndMissingLeadId() {
        Map<String, Object> payloadNoLead = new Map<String, Object>();
        payloadNoLead.put('firstName', 'NoLeadName');

        Test.startTest();
        // 1) Null payload – should just return, no exception
        Arelia_ManualProjectRequestController.updateLead(null);
        // 2) Payload without leadId – should also just return
        Arelia_ManualProjectRequestController.updateLead(payloadNoLead);
        Test.stopTest();

        System.assert(true, 'updateLead did not throw for null/missing leadId payloads.');
    }

    @IsTest
    static void testUpdateLeadLeadNotFound() {
        // Create and delete a lead to get a non-existing Id
        Lead temp = new Lead(
            FirstName = 'Temp',
            LastName  = 'Lead',
            Company   = 'Temp Co',
            Status    = 'Open - Not Contacted'
        );
        insert temp;
        Id deletedId = temp.Id;
        delete temp;

        Map<String, Object> payload = new Map<String, Object>();
        payload.put('leadId', deletedId);
        payload.put('firstName', 'ShouldNotError');

        // Method should just return without error (lead not found branch)
        Test.startTest();
        Arelia_ManualProjectRequestController.updateLead(payload);
        Test.stopTest();

        System.assert(true, 'updateLead handled non-existing lead gracefully.');
    }

    // ----------------------------------------------------------------------
    // Helper to get a safe picklist value (or null if none exist)
    // ----------------------------------------------------------------------
    private static String getAnyPicklistValue(Schema.SObjectField fieldRef) {
        Schema.DescribeFieldResult d = fieldRef.getDescribe();
        List<Schema.PicklistEntry> entries = d.getPicklistValues();
        return entries.isEmpty() ? null : entries[0].getValue();
    }

    // ----------------------------------------------------------------------
    // updateLead – successful update path
    // ----------------------------------------------------------------------
    @IsTest
    static void testUpdateLeadSuccess() {
        Lead setupLead = [
            SELECT Id,
                   FirstName,
                   LastName,
                   Email,
                   Phone,
                   Company,
                   Project_Request_Submitted__c
            FROM Lead
            LIMIT 1
        ];

        // Use real picklist values from the org to avoid restricted-picklist errors
        String validQuotationType = getAnyPicklistValue(Lead.Project_Request_Quotation_Type__c);
        String validScope         = getAnyPicklistValue(Lead.Project_Scope__c);
        String validType          = getAnyPicklistValue(Lead.Type_Of_Project__c);
        String validPlanLevel     = getAnyPicklistValue(Lead.Plan_Level__c);

        Map<String, Object> payload = new Map<String, Object>();
        payload.put('leadId', setupLead.Id);
        payload.put('firstName', 'UpdatedFirst');
        payload.put('lastName', 'UpdatedLast');
        payload.put('email', 'updated@example.com');
        payload.put('phone', '8888888888');
        payload.put('company', 'Updated Company');
        payload.put('typeOfProject', validType);
        payload.put('projectScope', validScope);
        payload.put('planLevel', validPlanLevel);
        payload.put('projectDescription', 'Some project description');
        payload.put('siteLocation', 'New Site Location');
        payload.put('quotationType', validQuotationType);
        payload.put('budget', 150000.0);       // Decimal
        payload.put('siteSpace', '1200 sqft'); // String

        Test.startTest();
        Arelia_ManualProjectRequestController.updateLead(payload);
        Test.stopTest();

        Lead updated = [
            SELECT FirstName,
                   LastName,
                   Email,
                   Phone,
                   Company,
                   Customer_Budget__c,
                   Project_Scope__c,
                   Plan_Level__c,
                   Project_Description__c,
                   Site_Location__c,
                   Project_Request_Quotation_Type__c,
                   Site_Space__c,
                   Project_Request_Submitted__c
            FROM Lead
            WHERE Id = :setupLead.Id
        ];

        System.assertEquals('UpdatedFirst', updated.FirstName, 'FirstName should be updated.');
        System.assertEquals('UpdatedLast', updated.LastName, 'LastName should be updated.');
        System.assertEquals('updated@example.com', updated.Email, 'Email should be updated.');
        System.assertEquals('8888888888', updated.Phone, 'Phone should be updated.');
        System.assertEquals('Updated Company', updated.Company, 'Company should be updated.');
        System.assertEquals(150000.0, updated.Customer_Budget__c, 'Budget should be updated.');

        // These asserts only check that something was set (if picklists exist in org)
        if (validScope != null) {
            System.assertEquals(validScope, updated.Project_Scope__c, 'Scope should be updated.');
        }
        if (validPlanLevel != null) {
            System.assertEquals(validPlanLevel, updated.Plan_Level__c, 'Plan level should be updated.');
        }
        if (validQuotationType != null) {
            System.assertEquals(validQuotationType, updated.Project_Request_Quotation_Type__c,
                'Quotation type should be updated.');
        }

        System.assertEquals('Some project description', updated.Project_Description__c,
            'Project description should be updated.');
        System.assertEquals('New Site Location', updated.Site_Location__c, 'Site location updated.');
        System.assertEquals('1200 sqft', updated.Site_Space__c, 'Site space should be updated.');
        System.assertEquals(true, updated.Project_Request_Submitted__c,
            'Lead should be marked as submitted.');
    }

    // ----------------------------------------------------------------------
    // updateLead – prevent second submission
    // ----------------------------------------------------------------------
    @IsTest
    static void testUpdateLeadPreventSecondSubmission() {
        // Create a lead already marked as submitted
        Lead alreadySubmitted = new Lead(
            FirstName                    = 'Already',
            LastName                     = 'Submitted',
            Company                      = 'Arelia',
            Status                       = 'Open - Not Contacted',
            Project_Request_Submitted__c = true
        );
        insert alreadySubmitted;

        Map<String, Object> payload = new Map<String, Object>();
        payload.put('leadId', alreadySubmitted.Id);
        payload.put('firstName', 'ShouldNotUpdate');

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            Arelia_ManualProjectRequestController.updateLead(payload);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
            // We only care that an AuraHandledException was thrown, not the exact message
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown,
            'AuraHandledException should be thrown for already submitted lead.');
    }
}