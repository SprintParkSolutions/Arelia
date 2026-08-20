/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementEmailService
 * Author          : <YourName>
 * Created Date    : Jun 26, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 26, 2026
 * Description     : Sends Vendor Agreement emails to the Vendor and Supervisor.
 *                   Template API names are read from Custom Labels and mapped to actual Email Template names because 
 *					 EmailTemplate.DeveloperName is not queryable in this org through Apex SOQL.
 * 					 
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 26, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */


public inherited sharing class VendorAgreementEmailService {

    public static void sendVendorAgreement(
        Vendor_Agreement__c agreementRecord
    ) {
        Vendor_Agreement__c agreementWithDetails =
            getAgreementWithDetails(agreementRecord.Id);

        if (String.isBlank(agreementWithDetails.Vendor_Email__c)) {
            throw new AuraHandledException(
                'Vendor email address is missing on the Vendor Agreement.'
            );
        }

        Id templateId =
            VendorAgreementUtil.getEmailTemplateIdFromLabel(
                System.Label.Vendor_Agreement_Vendor_Email_Template_API_Name,
                'Vendor_Agreement_Vendor_Email_Template_API_Name'
            );

        Messaging.SingleEmailMessage renderedEmail =
            Messaging.renderStoredEmailTemplate(
                templateId,
                UserInfo.getUserId(),
                agreementWithDetails.Id
            );

        Blob pdfBlob =
            VendorAgreementFileService.getLatestVersionData(
                agreementWithDetails.Unsigned_File_Id__c
            );

        Messaging.EmailFileAttachment attachment =
            new Messaging.EmailFileAttachment();

        attachment.setFileName(
            'Vendor Agreement - '
            + agreementWithDetails.Name
            + '.pdf'
        );

        attachment.setBody(pdfBlob);

        String htmlBody = renderedEmail.getHtmlBody();

        if (String.isBlank(htmlBody)) {
            htmlBody = renderedEmail.getPlainTextBody();
        }

        String plainTextBody = renderedEmail.getPlainTextBody();

        htmlBody = replaceTemplateTokens(
            htmlBody,
            agreementWithDetails
        );

        plainTextBody = replaceTemplateTokens(
            plainTextBody,
            agreementWithDetails
        );

        String emailSubject = replaceTemplateTokens(
            renderedEmail.getSubject(),
            agreementWithDetails
        );

        Messaging.SingleEmailMessage emailMessage =
            new Messaging.SingleEmailMessage();

        emailMessage.setToAddresses(
            new List<String>{
                agreementWithDetails.Vendor_Email__c
            }
        );

        emailMessage.setSubject(emailSubject);
        emailMessage.setHtmlBody(htmlBody);
        emailMessage.setPlainTextBody(plainTextBody);
        emailMessage.setOrgWideEmailAddressId(
            VendorAgreementUtil.getOrgWideEmailAddressId()
        );
        emailMessage.setSaveAsActivity(false);
        emailMessage.setFileAttachments(
            new List<Messaging.EmailFileAttachment>{ attachment }
        );

        sendEmail(emailMessage);
    }

    public static void sendSignedAgreementToSupervisor(
        Vendor_Agreement__c agreementRecord
    ) {
        Vendor_Agreement__c agreementWithDetails =
            getAgreementWithDetails(agreementRecord.Id);

        if (
            String.isBlank(
                agreementWithDetails.Supervisor_Email__c
            )
        ) {
            throw new AuraHandledException(
                'Supervisor email address is missing on the Vendor Agreement.'
            );
        }

        Id templateId =
            VendorAgreementUtil.getEmailTemplateIdFromLabel(
                System.Label.Vendor_Agreement_Supervisor_Email_Template_API_Name,
                'Vendor_Agreement_Supervisor_Email_Template_API_Name'
            );

        Messaging.SingleEmailMessage renderedEmail =
            Messaging.renderStoredEmailTemplate(
                templateId,
                UserInfo.getUserId(),
                agreementWithDetails.Id
            );

        Blob pdfBlob =
            VendorAgreementFileService.getLatestVersionData(
                agreementWithDetails.Signed_File_Id__c
            );

        Messaging.EmailFileAttachment attachment =
            new Messaging.EmailFileAttachment();

        attachment.setFileName(
            'Signed Vendor Agreement - '
            + agreementWithDetails.Name
            + '.pdf'
        );

        attachment.setBody(pdfBlob);

        String htmlBody = renderedEmail.getHtmlBody();

        if (String.isBlank(htmlBody)) {
            htmlBody = renderedEmail.getPlainTextBody();
        }

        String plainTextBody = renderedEmail.getPlainTextBody();

        htmlBody = replaceTemplateTokens(
            htmlBody,
            agreementWithDetails
        );

        plainTextBody = replaceTemplateTokens(
            plainTextBody,
            agreementWithDetails
        );

        String emailSubject = replaceTemplateTokens(
            renderedEmail.getSubject(),
            agreementWithDetails
        );

        Messaging.SingleEmailMessage emailMessage =
            new Messaging.SingleEmailMessage();

        emailMessage.setToAddresses(
            new List<String>{
                agreementWithDetails.Supervisor_Email__c
            }
        );

        emailMessage.setSubject(emailSubject);
        emailMessage.setHtmlBody(htmlBody);
        emailMessage.setPlainTextBody(plainTextBody);
        emailMessage.setOrgWideEmailAddressId(
            VendorAgreementUtil.getOrgWideEmailAddressId()
        );
        emailMessage.setSaveAsActivity(false);
        emailMessage.setFileAttachments(
            new List<Messaging.EmailFileAttachment>{ attachment }
        );

        sendEmail(emailMessage);
    }

    private static Vendor_Agreement__c getAgreementWithDetails(
        Id agreementId
    ) {
        List<Vendor_Agreement__c> agreements = [
            SELECT Id,
                   Name,
                   Vendor_Email__c,
                   Supervisor_Email__c,
                   Supervisor_Name__c,
                   Signing_Link__c,
                   Unsigned_File_Id__c,
                   Signed_File_Id__c,
                   Vendor__r.Name
            FROM Vendor_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];

        if (agreements.isEmpty()) {
            throw new AuraHandledException(
                'Vendor Agreement record was not found.'
            );
        }

        return agreements[0];
    }

    private static String replaceTemplateTokens(
        String value,
        Vendor_Agreement__c agreementRecord
    ) {
        if (String.isBlank(value)) {
            return '';
        }

        String vendorName = agreementRecord.Vendor__r == null
            ? ''
            : agreementRecord.Vendor__r.Name;

        String supervisorName =
            String.isBlank(agreementRecord.Supervisor_Name__c)
                ? ''
                : agreementRecord.Supervisor_Name__c;

        String signingLink =
            String.isBlank(agreementRecord.Signing_Link__c)
                ? ''
                : agreementRecord.Signing_Link__c;

        return value
            .replace('[[VENDOR_NAME]]', vendorName)
            .replace('[[SUPERVISOR_NAME]]', supervisorName)
            .replace('[[AGREEMENT_NAME]]', agreementRecord.Name)
            .replace('[[SIGNING_LINK]]', signingLink);
    }

    private static void sendEmail(
        Messaging.SingleEmailMessage emailMessage
    ) {
        Messaging.SendEmailResult[] results = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ emailMessage }
        );

        if (results == null || results.isEmpty()) {
            throw new AuraHandledException(
                'Email could not be sent.'
            );
        }

        if (!results[0].isSuccess()) {
            String errorMessage = 'Email could not be sent.';

            if (
                results[0].getErrors() != null
                && !results[0].getErrors().isEmpty()
            ) {
                errorMessage =
                    results[0].getErrors()[0].getMessage();
            }

            throw new AuraHandledException(errorMessage);
        }
    }
}