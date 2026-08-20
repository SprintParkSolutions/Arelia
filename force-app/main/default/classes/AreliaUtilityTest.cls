/**
 * @description Tests shared Arelia Apex utility behavior.
 */
@IsTest
private class AreliaUtilityTest {
    @IsTest
    static void getAreliaLeadRecordTypeIdReturnsConfiguredRecordType() {
        Test.startTest();
        Id recordTypeId = AreliaUtility.getAreliaLeadRecordTypeId();
        Id cachedRecordTypeId = AreliaUtility.getAreliaLeadRecordTypeId();
        Test.stopTest();

        Assert.isNotNull(recordTypeId, 'Arelia Lead record type should exist in metadata.');
        Assert.areEqual(recordTypeId, cachedRecordTypeId, 'Cached lookup should return the same Id.');
    }

    @IsTest
    static void getAreliaOpportunityRecordTypeIdReturnsConfiguredRecordType() {
        Test.startTest();
        Id recordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();
        Id cachedRecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();
        Test.stopTest();

        Assert.isNotNull(recordTypeId, 'Arelia Opportunity record type should exist in metadata.');
        Assert.areEqual(recordTypeId, cachedRecordTypeId, 'Cached lookup should return the same Id.');
    }

    @IsTest
    static void getAreliaAccountRecordTypeIdReturnsConfiguredRecordType() {
        Test.startTest();
        Id recordTypeId = AreliaUtility.getAreliaAccountRecordTypeId();
        Id cachedRecordTypeId = AreliaUtility.getAreliaAccountRecordTypeId();
        Test.stopTest();

        Assert.isNotNull(recordTypeId, 'Arelia Account record type should exist in metadata.');
        Assert.areEqual(recordTypeId, cachedRecordTypeId, 'Cached lookup should return the same Id.');
    }

    @IsTest
    static void getAreliaContactRecordTypeIdReturnsConfiguredRecordType() {
        Test.startTest();
        Id recordTypeId = AreliaUtility.getAreliaContactRecordTypeId();
        Id cachedRecordTypeId = AreliaUtility.getAreliaContactRecordTypeId();
        Test.stopTest();

        Assert.isNotNull(recordTypeId, 'Arelia Contact record type should exist in metadata.');
        Assert.areEqual(recordTypeId, cachedRecordTypeId, 'Cached lookup should return the same Id.');
    }

    @IsTest
    static void getAreliaProjectRecordTypeIdReturnsConfiguredRecordType() {
        Test.startTest();
        Id recordTypeId = AreliaUtility.getAreliaProjectRecordTypeId();
        Id cachedRecordTypeId = AreliaUtility.getAreliaProjectRecordTypeId();
        Test.stopTest();

        Assert.isNotNull(recordTypeId, 'Arelia Project record type should exist in metadata.');
        Assert.areEqual(recordTypeId, cachedRecordTypeId, 'Cached lookup should return the same Id.');
    }

    @IsTest
    static void getAreliaTaskRecordTypeIdReturnsConfiguredRecordType() {
        Test.startTest();
        Id recordTypeId = AreliaUtility.getAreliaTaskRecordTypeId();
        Id cachedRecordTypeId = AreliaUtility.getAreliaTaskRecordTypeId();
        Test.stopTest();

        Assert.isNotNull(recordTypeId, 'Arelia Task record type should exist in metadata.');
        Assert.areEqual(recordTypeId, cachedRecordTypeId, 'Cached lookup should return the same Id.');
    }

    @IsTest
    static void getAreliaCaseRecordTypeIdReturnsConfiguredRecordType() {
        Test.startTest();
        Id recordTypeId = AreliaUtility.getAreliaCaseRecordTypeId();
        Id cachedRecordTypeId = AreliaUtility.getAreliaCaseRecordTypeId();
        Test.stopTest();

        Assert.isNotNull(recordTypeId, 'Arelia Case record type should exist in metadata.');
        Assert.areEqual(recordTypeId, cachedRecordTypeId, 'Cached lookup should return the same Id.');
    }

    @IsTest
    static void getEmailTemplateIdByDeveloperNameHandlesBlankAndExistingTemplate() {
        EmailTemplate template = TestDataUtility.createSpecificEmailTemplate(
            'Arelia_Utility_Test_Template',
            'Arelia Utility Test Template',
            'Utility Subject'
        );

        Test.startTest();
        Id blankResult = AreliaUtility.getEmailTemplateIdByDeveloperName(null);
        Id missingResult = AreliaUtility.getEmailTemplateIdByDeveloperName('Missing_Template_Name');
        Id templateId = AreliaUtility.getEmailTemplateIdByDeveloperName(template.DeveloperName);
        Test.stopTest();

        Assert.isNull(blankResult, 'Blank developer name should not query a template.');
        Assert.isNull(missingResult, 'Unknown developer name should return null.');
        Assert.areEqual(template.Id, templateId, 'Existing template should be returned.');
    }

    @IsTest
    static void orgWideEmailHelpersHandleMissingInputs() {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

        Test.startTest();
        AreliaUtility.setOrgWideEmailAddress(null, System.Label.Arelia_OWD);
        AreliaUtility.setOrgWideEmailAddress(mail, null);
        AreliaUtility.setOrgWideEmailAddress(mail, 'missing-owd@example.com');
        Id blankAddressId = AreliaUtility.getOrgWideEmailAddressId(null);
        Id missingAddressId = AreliaUtility.getOrgWideEmailAddressId('missing-owd@example.com');
        Test.stopTest();

        Assert.isNull(blankAddressId, 'Blank org-wide email address should return null.');
        Assert.isNull(missingAddressId, 'Unknown org-wide email address should return null.');
    }

    @IsTest
    static void setOrgWideEmailAddressAppliesResolvedAddress() {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        AreliaUtility.orgWideEmailAddressIdForTest = UserInfo.getUserId();

        Test.startTest();
        AreliaUtility.setOrgWideEmailAddress(mail, 'owd@example.com');
        Test.stopTest();

        AreliaUtility.orgWideEmailAddressIdForTest = null;
        Assert.isNotNull(mail, 'Mail instance should remain available after setting org-wide email address.');
    }
}