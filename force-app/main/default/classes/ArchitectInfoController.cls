/**
 * @description Handles architect detail updates and architect email delivery for Arelia Opportunity records.
 * @author Arelia Space
 * @last modified on 05-11-2026
 */
public with sharing class ArchitectInfoController {
    private static final String ARCHITECT_EMAIL_TEMPLATE_DEVELOPER_NAME = 'Architect_Opportunity_Mail';
    private static final String ERROR_MISSING_PARAMETERS =
        'Required parameters are missing. Opportunity Id and Architect Email are required.';
    private static final String ERROR_TEMPLATE_NOT_FOUND =
        'The email template Architect_Opportunity_Mail could not be found.';
    private static final String ERROR_UNSUPPORTED_RECORD_TYPE =
        'Architect email is supported only for Arelia opportunities.';
    @TestVisible
    private static String templateDeveloperName = ARCHITECT_EMAIL_TEMPLATE_DEVELOPER_NAME;

    /**
     * @description Updates architect fields on an Arelia Opportunity and sends the architect email template.
     * @param recordId Opportunity Id.
     * @param architectName Architect name to save on the Opportunity.
     * @param architectEmail Architect email to save and send the email to.
     * @param architectPhone Architect phone number to save on the Opportunity.
     */
    @AuraEnabled
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static void updateAndSendEmail(
        Id recordId,
        String architectName,
        String architectEmail,
        String architectPhone
    ) {
        validateRequest(recordId, architectEmail);

        Savepoint savepointReference = Database.setSavepoint();

        try {
            validateAreliaOpportunity(recordId);
            updateOpportunityArchitectDetails(
                new Opportunity(
                    Id = recordId,
                    Architect_Name__c = architectName,
                    Architect_Email__c = architectEmail,
                    Architect_Contact__c = architectPhone
                )
            );
            sendArchitectEmail(recordId, architectEmail);
        } catch (Exception ex) {
            Database.rollback(savepointReference);
            throw buildAuraHandledException(ex.getMessage());
        }
    }

    private static void validateRequest(Id recordId, String architectEmail) {
        if (recordId == null || String.isBlank(architectEmail)) {
            throw buildAuraHandledException(ERROR_MISSING_PARAMETERS);
        }
    }

    private static void validateAreliaOpportunity(Id recordId) {
        Id areliaOpportunityRecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();

        if (
            areliaOpportunityRecordTypeId == null ||
            !hasAreliaOpportunity(recordId, areliaOpportunityRecordTypeId)
        ) {
            throw buildAuraHandledException(ERROR_UNSUPPORTED_RECORD_TYPE);
        }
    }

    private static Boolean hasAreliaOpportunity(Id recordId, Id areliaOpportunityRecordTypeId) {
        return ![SELECT Id FROM Opportunity WHERE Id = :recordId
        AND RecordTypeId = :areliaOpportunityRecordTypeId LIMIT 1]
        .isEmpty();
    }

    private static void updateOpportunityArchitectDetails(Opportunity oppToUpdate) {
        update as user oppToUpdate;
    }

    private static void sendArchitectEmail(Id recordId, String architectEmail) {
        Messaging.SingleEmailMessage mail = buildArchitectEmail(recordId, architectEmail);
        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

        if (!results[0].isSuccess()) {
            throw buildAuraHandledException(results[0].getErrors().isEmpty() ? 'Unable to send architect email.' : results[0].getErrors()[0].getMessage());
        }
    }

    private static Messaging.SingleEmailMessage buildArchitectEmail(Id recordId, String architectEmail) {
        Messaging.SingleEmailMessage renderedMail = Messaging.renderStoredEmailTemplate(
            getArchitectEmailTemplateId(),
            null,
            recordId
        );

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ architectEmail });
        mail.setSubject(renderedMail.getSubject());
        mail.setHtmlBody(renderedMail.getHtmlBody());
        mail.setPlainTextBody(renderedMail.getPlainTextBody());
        mail.setSaveAsActivity(false);
        AreliaUtility.setOrgWideEmailAddress(mail, System.Label.Arelia_OWD);
        return mail;
    }

    private static Id getArchitectEmailTemplateId() {
        Id templateId = AreliaUtility.getEmailTemplateIdByDeveloperName(
            templateDeveloperName
        );

        if (templateId == null) {
            throw buildAuraHandledException(ERROR_TEMPLATE_NOT_FOUND);
        }

        return templateId;
    }

    private static AuraHandledException buildAuraHandledException(String message) {
        AuraHandledException auraException = new AuraHandledException(message);
        auraException.setMessage(message);
        return auraException;
    }
}