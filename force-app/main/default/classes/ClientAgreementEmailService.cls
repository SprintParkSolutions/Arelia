public inherited sharing class ClientAgreementEmailService {

    private static final String DEBUG_PREFIX = 'CLIENT_AGREEMENT_EMAIL_DEBUG: ';

    public class EmailRequest {
        public String toAddress;
        public String templateDeveloperName;
        public Id orgWideEmailAddressId;
        public Id attachmentContentVersionId;
        public List<Id> entityAttachmentContentVersionIds;
        public String attachmentFileName;
        public String attachmentBase64;
        public String attachmentContentType;
        public List<EmailAttachment> additionalAttachments;
        public Map<String, String> mergeValues;
    }

    public class EmailAttachment {
        public String fileName;
        public String base64Data;
        public String contentType;
    }

    private class TemplateContent {
        public String subject;
        public String htmlBody;
    }

    public static void sendEmail(EmailRequest req) {
        if (req == null) {
            throw new AuraHandledException('Email request is missing.');
        }

        if (String.isBlank(req.toAddress)) {
            throw new AuraHandledException('Recipient email is missing.');
        }

        TemplateContent templateContent =
            getEmailTemplateContentSafe(req.templateDeveloperName);

        String subject = templateContent.subject;
        String htmlBody = templateContent.htmlBody;

        if (String.isBlank(subject)) {
            subject = 'Client Agreement';
        }

        if (String.isBlank(htmlBody)) {
            htmlBody = 'Please find the attached client agreement.';
        }

        if (req.mergeValues != null) {
            for (String key : req.mergeValues.keySet()) {
                String token = '{{' + key + '}}';
                String value = req.mergeValues.get(key);

                if (value == null) {
                    value = '';
                }

                subject = subject.replace(token, value);
                htmlBody = htmlBody.replace(token, value);
            }
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ req.toAddress });
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);

        if (req.orgWideEmailAddressId != null) {
            mail.setOrgWideEmailAddressId(req.orgWideEmailAddressId);
        }

        List<Id> entityAttachmentIds = new List<Id>();

        if (req.attachmentContentVersionId != null) {
            entityAttachmentIds.add(req.attachmentContentVersionId);
        }

        if (req.entityAttachmentContentVersionIds != null
            && !req.entityAttachmentContentVersionIds.isEmpty()) {
            entityAttachmentIds.addAll(req.entityAttachmentContentVersionIds);
        }

        if (!entityAttachmentIds.isEmpty()) {
            mail.setEntityAttachments(entityAttachmentIds);
        }

        List<Messaging.EmailFileAttachment> fileAttachments =
            new List<Messaging.EmailFileAttachment>();

        if (!String.isBlank(req.attachmentBase64)) {
            fileAttachments.add(
                buildEmailFileAttachment(
                    req.attachmentFileName,
                    req.attachmentBase64,
                    req.attachmentContentType
                )
            );
        }

        if (req.additionalAttachments != null
            && !req.additionalAttachments.isEmpty()) {
            for (EmailAttachment additionalAttachment : req.additionalAttachments) {
                if (additionalAttachment == null
                    || String.isBlank(additionalAttachment.base64Data)) {
                    continue;
                }

                fileAttachments.add(
                    buildEmailFileAttachment(
                        additionalAttachment.fileName,
                        additionalAttachment.base64Data,
                        additionalAttachment.contentType
                    )
                );
            }
        }

        if (!fileAttachments.isEmpty()) {
            mail.setFileAttachments(fileAttachments);
        }

        Messaging.SendEmailResult[] results =
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });

        if (results == null || results.isEmpty()) {
            throw new AuraHandledException('Email send failed. No send result returned.');
        }

        if (!results[0].isSuccess()) {
            String errorMessage = 'Email send failed.';

            if (results[0].getErrors() != null
                && !results[0].getErrors().isEmpty()) {
                errorMessage = results[0].getErrors()[0].getMessage();
            }

            throw new AuraHandledException(errorMessage);
        }
    }

    private static TemplateContent getEmailTemplateContentSafe(String developerName) {
        TemplateContent content = new TemplateContent();

        content.subject = 'Client Agreement for {{OPPORTUNITY_NAME}}';
        content.htmlBody =
            '<p>Dear {{LEAD_NAME}},</p>'
            + '<p>Please find attached the client agreement for {{OPPORTUNITY_NAME}}.</p>'
            + '<p>Please review and sign using the link below:</p>'
            + '<p><a href="{{SIGNING_URL}}">Open and Sign Client Agreement</a></p>'
            + '<p>Client Email: {{CLIENT_EMAIL}}</p>'
            + '<p>Supervisor Email: {{SUPERVISOR_EMAIL}}</p>';

        if (String.isBlank(developerName)) {
            System.debug(
                LoggingLevel.ERROR,
                DEBUG_PREFIX + 'Template DeveloperName is blank. Using fallback email body.'
            );
            return content;
        }

        try {
            Map<String, Schema.SObjectField> emailTemplateFields =
                Schema.SObjectType.EmailTemplate.fields.getMap();

            List<String> fieldsToQuery = new List<String>{
                'Id',
                'Subject',
                'Body',
                'DeveloperName'
            };

            if (emailTemplateFields.containsKey('HtmlValue')) {
                fieldsToQuery.add('HtmlValue');
            }

            if (emailTemplateFields.containsKey('Markup')) {
                fieldsToQuery.add('Markup');
            }

            String soql =
                'SELECT ' + String.join(fieldsToQuery, ',') +
                ' FROM EmailTemplate' +
                ' WHERE DeveloperName = :developerName' +
                ' LIMIT 1';

            List<EmailTemplate> templates = Database.query(soql);

            if (templates.isEmpty()) {
                System.debug(
                    LoggingLevel.ERROR,
                    DEBUG_PREFIX + 'No EmailTemplate found. DeveloperName=' + developerName
                );
                return content;
            }

            EmailTemplate templateRecord = templates[0];

            if (templateRecord.get('Subject') != null) {
                content.subject = String.valueOf(templateRecord.get('Subject'));
            }

            if (emailTemplateFields.containsKey('HtmlValue')
                && templateRecord.get('HtmlValue') != null) {
                content.htmlBody = String.valueOf(templateRecord.get('HtmlValue'));
            } else if (emailTemplateFields.containsKey('Markup')
                && templateRecord.get('Markup') != null) {
                content.htmlBody = String.valueOf(templateRecord.get('Markup'));
            } else if (templateRecord.get('Body') != null) {
                content.htmlBody = String.valueOf(templateRecord.get('Body'));
            }

            return content;
        } catch (QueryException queryExceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                DEBUG_PREFIX + 'EmailTemplate query not supported for this user/context. '
                + queryExceptionRecord.getMessage()
            );
            return content;
        } catch (Exception exceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                DEBUG_PREFIX + 'EmailTemplate lookup failed. '
                + exceptionRecord.getMessage()
            );
            return content;
        }
    }

    private static Messaging.EmailFileAttachment buildEmailFileAttachment(
        String fileName,
        String base64Data,
        String contentType
    ) {
        if (String.isBlank(base64Data)) {
            throw new AuraHandledException('Email attachment content is missing.');
        }

        String normalizedContentType = normalizeContentType(fileName, contentType);
        String normalizedFileName = normalizeFileName(fileName, normalizedContentType);

        String cleanedBase64 = base64Data;

        if (cleanedBase64.contains(',')) {
            cleanedBase64 = cleanedBase64.substringAfter(',');
        }

        Blob fileBody;

        try {
            fileBody = EncodingUtil.base64Decode(cleanedBase64);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Invalid email attachment Base64 content: ' + e.getMessage()
            );
        }

        Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
        efa.setFileName(normalizedFileName);
        efa.setContentType(normalizedContentType);
        efa.setBody(fileBody);

        return efa;
    }

    private static String normalizeContentType(String fileName, String contentType) {
        if (!String.isBlank(contentType)) {
            String ct = contentType.trim().toLowerCase();

            if (ct == 'application/pdf') {
                return 'application/pdf';
            }

            if (ct == 'image/png') {
                return 'image/png';
            }

            if (ct == 'image/jpeg' || ct == 'image/jpg') {
                return 'image/jpeg';
            }
        }

        String lowerFileName = String.isBlank(fileName)
            ? ''
            : fileName.trim().toLowerCase();

        if (lowerFileName.endsWith('.pdf')) {
            return 'application/pdf';
        }

        if (lowerFileName.endsWith('.png')) {
            return 'image/png';
        }

        if (lowerFileName.endsWith('.jpg') || lowerFileName.endsWith('.jpeg')) {
            return 'image/jpeg';
        }

        return 'application/octet-stream';
    }

    private static String normalizeFileName(String fileName, String contentType) {
        String cleaned = sanitizeFileName(fileName);

        if (String.isBlank(cleaned)) {
            cleaned = 'Attachment';
        }

        String lowerName = cleaned.toLowerCase();
        String lowerContentType = String.isBlank(contentType)
            ? ''
            : contentType.toLowerCase();

        if (lowerContentType == 'application/pdf'
            && !lowerName.endsWith('.pdf')) {
            cleaned += '.pdf';
        } else if (lowerContentType == 'image/png'
            && !lowerName.endsWith('.png')) {
            cleaned += '.png';
        } else if (lowerContentType == 'image/jpeg'
            && !lowerName.endsWith('.jpg')
            && !lowerName.endsWith('.jpeg')) {
            cleaned += '.jpg';
        }

        return cleaned;
    }

    private static String sanitizeFileName(String fileName) {
        if (String.isBlank(fileName)) {
            return 'Attachment.pdf';
        }

        String cleaned = fileName.trim();

        cleaned = cleaned.replace('\\', '_');
        cleaned = cleaned.replace('/', '_');
        cleaned = cleaned.replace(':', '_');
        cleaned = cleaned.replace('*', '_');
        cleaned = cleaned.replace('?', '_');
        cleaned = cleaned.replace('"', '_');
        cleaned = cleaned.replace('<', '_');
        cleaned = cleaned.replace('>', '_');
        cleaned = cleaned.replace('|', '_');

        return cleaned;
    }

    public static Id getOrgWideEmailAddressIdFromLabel() {
        String senderValue = System.Label.Arelia_OWD_ID;

        System.debug(
            LoggingLevel.ERROR,
            DEBUG_PREFIX + 'OWD label value=' + senderValue
        );

        if (String.isBlank(senderValue)) {
            System.debug(
                LoggingLevel.ERROR,
                DEBUG_PREFIX + 'OWD label is blank. Email will be sent without OWD.'
            );
            return null;
        }

        String trimmedValue = senderValue.trim();

        /*
        * Recommended for Partner Community users:
        * Store OrgWideEmailAddress Id directly in Custom Label.
        * This avoids querying OrgWideEmailAddress, which external users cannot access.
        */
        if (trimmedValue.startsWith('0D2')) {
            System.debug(
                LoggingLevel.ERROR,
                DEBUG_PREFIX + 'Using OWD Id directly from label.'
            );
            return (Id) trimmedValue;
        }

        try {
            List<SObject> owds = Database.query(
                'SELECT Id, Address, DisplayName ' +
                'FROM OrgWideEmailAddress ' +
                'WHERE Address = :trimmedValue ' +
                'LIMIT 1'
            );

            if (owds.isEmpty()) {
                System.debug(
                    LoggingLevel.ERROR,
                    DEBUG_PREFIX + 'No OWD found for email=' + trimmedValue
                );
                return null;
            }

            return (Id) owds[0].get('Id');
        } catch (Exception exceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                DEBUG_PREFIX + 'OWD lookup skipped. ' + exceptionRecord.getMessage()
            );
            return null;
        }
    }
}

/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementEmailService
 * Author          : <YourName>
 * Created Date    : Jun 10, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 10, 2026
 * Description     : Sends Client Agreement emails using template body, org-wide email,
 *                   Salesforce File entity attachments, and optional raw attachments.
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 10, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */


// public inherited sharing class ClientAgreementEmailService {

//     public class EmailRequest {
//         public String toAddress;
//         public String templateDeveloperName;
//         public Id orgWideEmailAddressId;

//         /*
//          * Existing Salesforce File attachment by ContentVersion Id.
//          */
//         public Id attachmentContentVersionId;

//         /*
//          * Additional Salesforce File attachments by ContentVersion Id.
//          * Used for supporting images/PDFs already stored as Salesforce Files.
//          */
//         public List<Id> entityAttachmentContentVersionIds;

//         /*
//          * Raw attachment.
//          * Kept for backward compatibility and for generated/signed PDFs where raw Base64 is still used.
//          */
//         public String attachmentFileName;
//         public String attachmentBase64;
//         public String attachmentContentType;

//         /*
//          * Additional raw attachments.
//          * Kept for backward compatibility.
//          */
//         public List<EmailAttachment> additionalAttachments;

//         public Map<String, String> mergeValues;
//     }

//     public class EmailAttachment {
//         public String fileName;
//         public String base64Data;
//         public String contentType;
//     }

//     public static void sendEmail(EmailRequest req) {
//         if (req == null) {
//             throw new AuraHandledException('Email request is missing.');
//         }

//         if (String.isBlank(req.toAddress)) {
//             throw new AuraHandledException('Recipient email is missing.');
//         }

//         if (String.isBlank(req.templateDeveloperName)) {
//             throw new AuraHandledException('Email template API name / DeveloperName is missing.');
//         }

//         EmailTemplate templateRecord =
//             getEmailTemplateByDeveloperName(req.templateDeveloperName);

//         String subject = '';
//         String htmlBody = '';

//         if (templateRecord.get('Subject') != null) {
//             subject = String.valueOf(templateRecord.get('Subject'));
//         }

//         Map<String, Schema.SObjectField> emailTemplateFields =
//             Schema.SObjectType.EmailTemplate.fields.getMap();

//         if (emailTemplateFields.containsKey('HtmlValue')
//             && templateRecord.get('HtmlValue') != null) {
//             htmlBody = String.valueOf(templateRecord.get('HtmlValue'));
//         } else if (emailTemplateFields.containsKey('Markup')
//             && templateRecord.get('Markup') != null) {
//             htmlBody = String.valueOf(templateRecord.get('Markup'));
//         } else if (templateRecord.get('Body') != null) {
//             htmlBody = String.valueOf(templateRecord.get('Body'));
//         }

//         if (String.isBlank(subject)) {
//             subject = 'Client Agreement';
//         }

//         if (String.isBlank(htmlBody)) {
//             htmlBody = 'Please find the attached client agreement.';
//         }

//         if (req.mergeValues != null) {
//             for (String key : req.mergeValues.keySet()) {
//                 String token = '{{' + key + '}}';
//                 String value = req.mergeValues.get(key);

//                 if (value == null) {
//                     value = '';
//                 }

//                 subject = subject.replace(token, value);
//                 htmlBody = htmlBody.replace(token, value);
//             }
//         }

//         Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
//         mail.setToAddresses(new List<String>{ req.toAddress });
//         mail.setSubject(subject);
//         mail.setHtmlBody(htmlBody);

//         if (req.orgWideEmailAddressId != null) {
//             mail.setOrgWideEmailAddressId(req.orgWideEmailAddressId);
//         }

//         /*
//          * Attach Salesforce Files by ContentVersion Id.
//          * This preserves file type/extension better than raw Base64 for files already in Salesforce.
//          */
//         List<Id> entityAttachmentIds = new List<Id>();

//         if (req.attachmentContentVersionId != null) {
//             entityAttachmentIds.add(req.attachmentContentVersionId);
//         }

//         if (req.entityAttachmentContentVersionIds != null
//             && !req.entityAttachmentContentVersionIds.isEmpty()) {
//             entityAttachmentIds.addAll(req.entityAttachmentContentVersionIds);
//         }

//         if (!entityAttachmentIds.isEmpty()) {
//             mail.setEntityAttachments(entityAttachmentIds);
//         }

//         /*
//          * Raw file attachments.
//          * Kept for cases where Base64 content is intentionally used.
//          */
//         List<Messaging.EmailFileAttachment> fileAttachments =
//             new List<Messaging.EmailFileAttachment>();

//         if (!String.isBlank(req.attachmentBase64)) {
//             fileAttachments.add(
//                 buildEmailFileAttachment(
//                     req.attachmentFileName,
//                     req.attachmentBase64,
//                     req.attachmentContentType
//                 )
//             );
//         }

//         if (req.additionalAttachments != null
//             && !req.additionalAttachments.isEmpty()) {
//             for (EmailAttachment additionalAttachment : req.additionalAttachments) {
//                 if (additionalAttachment == null
//                     || String.isBlank(additionalAttachment.base64Data)) {
//                     continue;
//                 }

//                 fileAttachments.add(
//                     buildEmailFileAttachment(
//                         additionalAttachment.fileName,
//                         additionalAttachment.base64Data,
//                         additionalAttachment.contentType
//                     )
//                 );
//             }
//         }

//         if (!fileAttachments.isEmpty()) {
//             mail.setFileAttachments(fileAttachments);
//         }

//         Messaging.SendEmailResult[] results =
//             Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });

//         if (results == null || results.isEmpty()) {
//             throw new AuraHandledException('Email send failed. No send result returned.');
//         }

//         if (!results[0].isSuccess()) {
//             String errorMessage = 'Email send failed.';

//             if (results[0].getErrors() != null
//                 && !results[0].getErrors().isEmpty()) {
//                 errorMessage = results[0].getErrors()[0].getMessage();
//             }

//             throw new AuraHandledException(errorMessage);
//         }
//     }

//     private static Messaging.EmailFileAttachment buildEmailFileAttachment(
//         String fileName,
//         String base64Data,
//         String contentType
//     ) {
//         if (String.isBlank(base64Data)) {
//             throw new AuraHandledException('Email attachment content is missing.');
//         }

//         String normalizedContentType = normalizeContentType(fileName, contentType);
//         String normalizedFileName = normalizeFileName(fileName, normalizedContentType);

//         String cleanedBase64 = base64Data;

//         if (cleanedBase64.contains(',')) {
//             cleanedBase64 = cleanedBase64.substringAfter(',');
//         }

//         Blob fileBody;

//         try {
//             fileBody = EncodingUtil.base64Decode(cleanedBase64);
//         } catch (Exception e) {
//             throw new AuraHandledException(
//                 'Invalid email attachment Base64 content: ' + e.getMessage()
//             );
//         }

//         Messaging.EmailFileAttachment efa =
//             new Messaging.EmailFileAttachment();

//         efa.setFileName(normalizedFileName);
//         efa.setContentType(normalizedContentType);
//         efa.setBody(fileBody);

//         return efa;
//     }

//     private static String normalizeContentType(String fileName, String contentType) {
//         if (!String.isBlank(contentType)) {
//             String ct = contentType.trim().toLowerCase();

//             if (ct == 'application/pdf') {
//                 return 'application/pdf';
//             }

//             if (ct == 'image/png') {
//                 return 'image/png';
//             }

//             if (ct == 'image/jpeg' || ct == 'image/jpg') {
//                 return 'image/jpeg';
//             }
//         }

//         String lowerFileName = String.isBlank(fileName)
//             ? ''
//             : fileName.trim().toLowerCase();

//         if (lowerFileName.endsWith('.pdf')) {
//             return 'application/pdf';
//         }

//         if (lowerFileName.endsWith('.png')) {
//             return 'image/png';
//         }

//         if (lowerFileName.endsWith('.jpg') || lowerFileName.endsWith('.jpeg')) {
//             return 'image/jpeg';
//         }

//         return 'application/octet-stream';
//     }

//     private static String normalizeFileName(String fileName, String contentType) {
//         String cleaned = sanitizeFileName(fileName);

//         if (String.isBlank(cleaned)) {
//             cleaned = 'Attachment';
//         }

//         String lowerName = cleaned.toLowerCase();
//         String lowerContentType = String.isBlank(contentType)
//             ? ''
//             : contentType.toLowerCase();

//         if (lowerContentType == 'application/pdf'
//             && !lowerName.endsWith('.pdf')) {
//             cleaned += '.pdf';
//         } else if (lowerContentType == 'image/png'
//             && !lowerName.endsWith('.png')) {
//             cleaned += '.png';
//         } else if (lowerContentType == 'image/jpeg'
//             && !lowerName.endsWith('.jpg')
//             && !lowerName.endsWith('.jpeg')) {
//             cleaned += '.jpg';
//         }

//         return cleaned;
//     }

//     private static String sanitizeFileName(String fileName) {
//         if (String.isBlank(fileName)) {
//             return 'Attachment.pdf';
//         }

//         String cleaned = fileName.trim();

//         cleaned = cleaned.replace('\\', '_');
//         cleaned = cleaned.replace('/', '_');
//         cleaned = cleaned.replace(':', '_');
//         cleaned = cleaned.replace('*', '_');
//         cleaned = cleaned.replace('?', '_');
//         cleaned = cleaned.replace('"', '_');
//         cleaned = cleaned.replace('<', '_');
//         cleaned = cleaned.replace('>', '_');
//         cleaned = cleaned.replace('|', '_');

//         return cleaned;
//     }

//     private static EmailTemplate getEmailTemplateByDeveloperName(String developerName) {
//         Map<String, Schema.SObjectField> emailTemplateFields =
//             Schema.SObjectType.EmailTemplate.fields.getMap();

//         List<String> fieldsToQuery = new List<String>{
//             'Id',
//             'Subject',
//             'Body',
//             'DeveloperName'
//         };

//         if (emailTemplateFields.containsKey('HtmlValue')) {
//             fieldsToQuery.add('HtmlValue');
//         }

//         if (emailTemplateFields.containsKey('Markup')) {
//             fieldsToQuery.add('Markup');
//         }

//         String soql =
//             'SELECT ' + String.join(fieldsToQuery, ',') +
//             ' FROM EmailTemplate' +
//             ' WHERE DeveloperName = :developerName' +
//             ' LIMIT 1';

//         List<EmailTemplate> templates = Database.query(soql);

//         if (templates.isEmpty()) {
//             throw new AuraHandledException(
//                 'No Email Template found with DeveloperName: ' + developerName
//             );
//         }

//         return templates[0];
//     }

//     public static Id getOrgWideEmailAddressIdFromLabel() {
//         String senderEmail = System.Label.Arelia_OWD;

//         if (String.isBlank(senderEmail)) {
//             throw new AuraHandledException('OWD email custom label is blank.');
//         }

//         String soql =
//             'SELECT Id, Address, DisplayName ' +
//             'FROM OrgWideEmailAddress ' +
//             'WHERE Address = :senderEmail ' +
//             'LIMIT 1';

//         List<SObject> owds = Database.query(soql);

//         if (owds.isEmpty()) {
//             throw new AuraHandledException(
//                 'No Org-Wide Email Address found for: ' + senderEmail
//             );
//         }

//         return (Id) owds[0].get('Id');
//     }
// }