/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementService
 * Author          : <YourName>
 * Created Date    : Jun 26, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 26, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 26, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public with sharing class VendorAgreementService {

    public class AgreementResponse {
        @AuraEnabled public Id agreementId;
        @AuraEnabled public String agreementHtml;
        @AuraEnabled public String vendorName;
        @AuraEnabled public String vendorEmail;
        @AuraEnabled public String agreementStatus;
    }

    @AuraEnabled
    public static AgreementResponse getAgreement(
        Id vendorOpportunityId
    ) {
        Vendor_Opportunity__c vendorOpportunity =
            getVendorOpportunity(vendorOpportunityId);

        validateAreliaOpportunity(
            vendorOpportunity.Opportunity__r
        );

        Vendor_Agreement__c agreementRecord =
            getOrCreateAgreement(vendorOpportunity);

        return buildResponse(
            agreementRecord,
            vendorOpportunity.Vendor__r.Name
        );
    }

    @AuraEnabled
    public static AgreementResponse saveAgreement(
        Id vendorOpportunityId,
        String agreementHtml
    ) {
        Vendor_Opportunity__c vendorOpportunity =
            getVendorOpportunity(vendorOpportunityId);

        validateAreliaOpportunity(
            vendorOpportunity.Opportunity__r
        );

        Vendor_Agreement__c agreementRecord =
            getOrCreateAgreement(vendorOpportunity);

        if (
            agreementRecord.Agreement_Status__c
            == VendorAgreementConstants.STATUS_SIGNED
        ) {
            throw new AuraHandledException(
                'A signed Vendor Agreement cannot be edited.'
            );
        }

        agreementRecord.Agreement_HTML__c =
            VendorAgreementUtil.sanitizeHtml(agreementHtml);

        update agreementRecord;

        return buildResponse(
            agreementRecord,
            vendorOpportunity.Vendor__r.Name
        );
    }

    
    @AuraEnabled
    public static void sendAgreement(Id vendorOpportunityId) {
        Vendor_Opportunity__c vendorOpportunity =
            getVendorOpportunity(vendorOpportunityId);

        validateAreliaOpportunity(
            vendorOpportunity.Opportunity__r
        );

        Vendor_Agreement__c agreementRecord =
            getOrCreateAgreement(vendorOpportunity);

        if (String.isBlank(agreementRecord.Vendor_Email__c)) {
            throw new AuraHandledException(
                'Vendor email address is missing on the Vendor record.'
            );
        }

        if (
            agreementRecord.Agreement_Status__c
            == VendorAgreementConstants.STATUS_SIGNED
        ) {
            throw new AuraHandledException(
                'This Vendor Agreement has already been signed.'
            );
        }

        Id unsignedFileId =
            VendorAgreementFileService.createUnsignedAgreementPdf(
                agreementRecord
            );

        String signingUrl =
            VendorAgreementUtil.buildSigningUrl(
                agreementRecord.Id
            );

        agreementRecord.Unsigned_File_Id__c =
            String.valueOf(unsignedFileId);

        agreementRecord.Signing_Link__c =
            signingUrl;

        agreementRecord.Sent_Date__c = Date.today();

        agreementRecord.Agreement_Status__c =
            VendorAgreementConstants.STATUS_SENT;

        update agreementRecord;

        Vendor_Opportunity__c vendorOpportunityToUpdate =
            new Vendor_Opportunity__c(
                Id = vendorOpportunity.Id,
                Vendor_Agreement_Sent__c = true
            );

        update vendorOpportunityToUpdate;

        VendorAgreementEmailService.sendVendorAgreement(
            agreementRecord
        );
    }

    private static Vendor_Opportunity__c getVendorOpportunity(
        Id vendorOpportunityId
    ) {
        if (vendorOpportunityId == null) {
            throw new AuraHandledException(
                'Vendor Opportunity Id is required.'
            );
        }

        List<Vendor_Opportunity__c> vendorOpportunities = [
            SELECT Id,
                   Name,
                   Vendor_Category__c,
                   Opportunity__c,
                   Opportunity__r.Id,
                   Opportunity__r.Name,
                   Opportunity__r.RecordTypeId,
                   Opportunity__r.RecordType.DeveloperName,
                   Vendor__c,
                   Vendor__r.Id,
                   Vendor__r.Name,
                   Vendor__r.Email__c,
                   Vendor__r.Phone__c,
                   Vendor__r.Address__c,
                   Vendor_Agreement_Sent__c,
                   Vendor_Agreement_Signed__c
            FROM Vendor_Opportunity__c
            WHERE Id = :vendorOpportunityId
            LIMIT 1
        ];

        if (vendorOpportunities.isEmpty()) {
            throw new AuraHandledException(
                'Vendor Opportunity record was not found.'
            );
        }

        Vendor_Opportunity__c vendorOpportunity =
            vendorOpportunities[0];

        if (
            vendorOpportunity.Opportunity__c == null
            || vendorOpportunity.Vendor__c == null
        ) {
            throw new AuraHandledException(
                'Vendor Opportunity must have an Opportunity and Vendor.'
            );
        }

        return vendorOpportunity;
    }

    private static Vendor_Agreement__c getOrCreateAgreement(
        Vendor_Opportunity__c vendorOpportunity
    ) {
        List<Vendor_Agreement__c> agreements = [
            SELECT Id,
                   Name,
                   Agreement_HTML__c,
                   Agreement_Status__c,
                   Vendor_Email__c,
                   Supervisor_Email__c,
                   Supervisor_Name__c,
                   Signing_Link__c,
                   Vendor__c,
                   Vendor_Opportunity__c,
                   Opportunity__c,
                   Unsigned_File_Id__c,
                   Signed_File_Id__c,
                   Signing_Token__c,
                   Token_Expiry__c
            FROM Vendor_Agreement__c
            WHERE Vendor_Opportunity__c = :vendorOpportunity.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!agreements.isEmpty()) {
            Vendor_Agreement__c existingAgreement =
                agreements[0];

            populateMissingSupervisorName(
                existingAgreement,
                vendorOpportunity.Opportunity__c
            );

            return existingAgreement;
        }

        Vendor__c vendorRecord = [
            SELECT Id,
                   Name,
                   Phone__c,
                   Address__c,
                   Email__c
            FROM Vendor__c
            WHERE Id = :vendorOpportunity.Vendor__c
            LIMIT 1
        ];

        Opportunity opportunityRecord = [
            SELECT Id,
                   Name,
                   RecordTypeId,
                   RecordType.DeveloperName,
                   Supervisor_User__c,
                   Supervisor_User_Email__c,
                   Supervisor_User__r.Name
            FROM Opportunity
            WHERE Id = :vendorOpportunity.Opportunity__c
            LIMIT 1
        ];

        if (String.isBlank(vendorRecord.Email__c)) {
            throw new AuraHandledException(
                'Vendor email address is missing on the Vendor record.'
            );
        }

        if (
            String.isBlank(
                opportunityRecord.Supervisor_User_Email__c
            )
        ) {
            throw new AuraHandledException(
                'Supervisor email address is missing on the Opportunity record.'
            );
        }

        if (
            opportunityRecord.Supervisor_User__c == null
            || String.isBlank(
                opportunityRecord.Supervisor_User__r.Name
            )
        ) {
            throw new AuraHandledException(
                'Supervisor User is missing on the Opportunity record.'
            );
        }

        Vendor_Agreement__c agreementRecord =
            new Vendor_Agreement__c(
                Vendor_Opportunity__c = vendorOpportunity.Id,
                Opportunity__c = vendorOpportunity.Opportunity__c,
                Vendor__c = vendorOpportunity.Vendor__c,
                Agreement_HTML__c =
                    VendorAgreementTemplateService.buildAgreementHtml(
                        vendorOpportunity
                    ),
                Agreement_Status__c =
                    VendorAgreementConstants.STATUS_DRAFT,
                Vendor_Email__c = vendorRecord.Email__c,
                Supervisor_Email__c =
                    opportunityRecord.Supervisor_User_Email__c,
                Supervisor_Name__c =
                    opportunityRecord.Supervisor_User__r.Name
            );

        insert agreementRecord;

        return agreementRecord;
    }

    private static void populateMissingSupervisorName(
        Vendor_Agreement__c agreementRecord,
        Id opportunityId
    ) {
        if (!String.isBlank(agreementRecord.Supervisor_Name__c)) {
            return;
        }

        Opportunity opportunityRecord = [
            SELECT Id,
                   Supervisor_User__c,
                   Supervisor_User__r.Name
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        if (
            opportunityRecord.Supervisor_User__c == null
            || String.isBlank(
                opportunityRecord.Supervisor_User__r.Name
            )
        ) {
            throw new AuraHandledException(
                'Supervisor User is missing on the Opportunity record.'
            );
        }

        agreementRecord.Supervisor_Name__c =
            opportunityRecord.Supervisor_User__r.Name;

        update agreementRecord;
    }

    private static AgreementResponse buildResponse(
        Vendor_Agreement__c agreementRecord,
        String vendorName
    ) {
        AgreementResponse response = new AgreementResponse();

        response.agreementId = agreementRecord.Id;
        response.agreementHtml = agreementRecord.Agreement_HTML__c;
        response.vendorName = vendorName;
        response.vendorEmail = agreementRecord.Vendor_Email__c;
        response.agreementStatus =
            agreementRecord.Agreement_Status__c;

        return response;
    }

    private static void validateAreliaOpportunity(
        Opportunity opportunityRecord
    ) {
        if (
            !VendorAgreementUtil.isAreliaOpportunity(
                opportunityRecord
            )
        ) {
            throw new AuraHandledException(
                'Vendor Agreement is available only for Arelia Opportunities.'
            );
        }
    }
}