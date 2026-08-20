/**
 * @description Provides reusable utility methods for Arelia Apex services.
 * @author Arelia Space
 */
public with sharing class AreliaUtility {
    private static final String ARELIA_RECORD_TYPE_NAME = 'Arelia';
    @TestVisible
    private static Id orgWideEmailAddressIdForTest;

    /**
     * @description Resolves the Arelia Lead Record Type Id via schema describe.
     * @return Arelia Lead RecordType Id, or null when the Record Type is not available.
     */
    public static Id getAreliaLeadRecordTypeId() {
        Schema.RecordTypeInfo rtInfo = Lead.SObjectType.getDescribe()
            .getRecordTypeInfosByName().get(ARELIA_RECORD_TYPE_NAME);
        return rtInfo == null ? null : rtInfo.getRecordTypeId();
    }

    /**
     * @description Resolves the Arelia Opportunity Record Type Id via schema describe.
     * @return Arelia Opportunity RecordType Id, or null when the Record Type is not available.
     */
    public static Id getAreliaOpportunityRecordTypeId() {
        Schema.RecordTypeInfo rtInfo = Opportunity.SObjectType.getDescribe()
            .getRecordTypeInfosByName().get(ARELIA_RECORD_TYPE_NAME);
        return rtInfo == null ? null : rtInfo.getRecordTypeId();
    }

    /**
     * @description Resolves the Arelia Account Record Type Id via schema describe.
     * @return Arelia Account RecordType Id, or null when the Record Type is not available.
     */
    public static Id getAreliaAccountRecordTypeId() {
        Schema.RecordTypeInfo rtInfo = Account.SObjectType.getDescribe()
            .getRecordTypeInfosByName().get(ARELIA_RECORD_TYPE_NAME);
        return rtInfo == null ? null : rtInfo.getRecordTypeId();
    }

    /**
     * @description Resolves the Arelia Contact Record Type Id via schema describe.
     * @return Arelia Contact RecordType Id, or null when the Record Type is not available.
     */
    public static Id getAreliaContactRecordTypeId() {
        Schema.RecordTypeInfo rtInfo = Contact.SObjectType.getDescribe()
            .getRecordTypeInfosByName().get(ARELIA_RECORD_TYPE_NAME);
        return rtInfo == null ? null : rtInfo.getRecordTypeId();
    }

    /**
     * @description Resolves the Arelia Case Record Type Id via schema describe.
     * @return Arelia Case RecordType Id, or null when the Record Type is not available.
     */
    public static Id getAreliaCaseRecordTypeId() {
        Schema.RecordTypeInfo rtInfo = Case.SObjectType.getDescribe()
            .getRecordTypeInfosByName().get(ARELIA_RECORD_TYPE_NAME);
        return rtInfo == null ? null : rtInfo.getRecordTypeId();
    }

    /**
     * @description Resolves the Arelia Project Record Type Id via schema describe.
     * @return Arelia Project RecordType Id, or null when the Record Type is not available.
     */
    public static Id getAreliaProjectRecordTypeId() {
        Schema.RecordTypeInfo rtInfo = Project__c.SObjectType.getDescribe()
            .getRecordTypeInfosByName().get(ARELIA_RECORD_TYPE_NAME);
        return rtInfo == null ? null : rtInfo.getRecordTypeId();
    }

    /**
     * @description Resolves the Arelia Task Record Type Id via schema describe.
     * @return Arelia Task RecordType Id, or null when the Record Type is not available.
     */
    public static Id getAreliaTaskRecordTypeId() {
        Schema.RecordTypeInfo rtInfo = Task.SObjectType.getDescribe()
            .getRecordTypeInfosByName().get(ARELIA_RECORD_TYPE_NAME);
        return rtInfo == null ? null : rtInfo.getRecordTypeId();
    }

    /**
     * @description Queries an Email Template Id by DeveloperName.
     * @param templateDeveloperName EmailTemplate DeveloperName value.
     * @return Matching EmailTemplate Id, or null when no matching template exists.
     */
    public static Id getEmailTemplateIdByDeveloperName(String templateDeveloperName) {
        if (String.isBlank(templateDeveloperName)) {
            return null;
        }
        List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate
                                WHERE DeveloperName = :templateDeveloperName LIMIT 1];
        return templates.isEmpty() ? null : templates[0].Id;
    }

    /**
     * @description Applies an org-wide email address to an outbound email when the address exists.
     * @param mail Email message that should use the org-wide email address.
     * @param orgWideEmailAddress OrgWideEmailAddress.Address value to apply.
     */
    public static void setOrgWideEmailAddress(Messaging.SingleEmailMessage mail, String orgWideEmailAddress)
    {
        if (mail == null || String.isBlank(orgWideEmailAddress)) {
            return;
        }

        Id orgWideEmailAddressId = Test.isRunningTest() && orgWideEmailAddressIdForTest != null
            ? orgWideEmailAddressIdForTest : getOrgWideEmailAddressId(orgWideEmailAddress);

        if (orgWideEmailAddressId != null) {
            mail.setOrgWideEmailAddressId(orgWideEmailAddressId);
        }
    }

    /**
     * @description Queries an org-wide email address Id by email address.
     * @param orgWideEmailAddress OrgWideEmailAddress.Address value to query.
     * @return Matching OrgWideEmailAddress Id, or null when no matching address exists.
     */
    public static Id getOrgWideEmailAddressId(String orgWideEmailAddress) {
        if (String.isBlank(orgWideEmailAddress)) {
            return null;
        }
        List<OrgWideEmailAddress> owdAddresses = [SELECT Id FROM OrgWideEmailAddress
                                        WHERE Address = :orgWideEmailAddress LIMIT 1];
        return owdAddresses.isEmpty() ? null : owdAddresses[0].Id;
    }
}