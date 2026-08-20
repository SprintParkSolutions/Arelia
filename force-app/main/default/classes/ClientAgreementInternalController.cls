/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementInternalController
 * Author          : <YourName>
 * Created Date    : Jun 10, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 10, 2026
 * Description     : Internal controller for Send Client Agreement quick action.
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 10, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public with sharing class ClientAgreementInternalController {

    private static final String ARELIA_RECORD_TYPE_DEVELOPER_NAME = 'Arelia';

    @AuraEnabled(cacheable=false)
    public static ClientAgreementDTO.InitResponse getAgreementInitData(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }

        Opportunity opp = [
            SELECT Id,
                   Name,
                   Email__c,
                   Supervisor_User_Email__c,
                   RecordTypeId,
                   Lead_Name__c,
                   Lead_Phone__c,
                   Site_Location__c,
                   Supervisor_Estimated_Budget__c,
                   Re_Visit_Site_Supervisor_Estimate_Budget__c,
                   Project_Estimated_Completion_Months__c,
                   ReVisit_Site_Estimated_Completion_Months__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        List<Payment_Term__c> paymentTerms = [
            SELECT Id,
                Name,
                Percentage__c,
                Due_Date__c
            FROM Payment_Term__c
            WHERE Opportunity__c = :opp.Id
            ORDER BY Due_Date__c ASC, CreatedDate ASC
        ];

        validateAreliaOpportunity(opp);

        if (String.isBlank(opp.Email__c)) {
            throw new AuraHandledException('Client Email is missing on Opportunity.');
        }

        if (String.isBlank(opp.Supervisor_User_Email__c)) {
            throw new AuraHandledException('Supervisor Email is missing on Opportunity.');
        }

        ClientAgreementDTO.InitResponse response = new ClientAgreementDTO.InitResponse();
        response.opportunityId = opp.Id;
        response.opportunityName = opp.Name;
        response.clientEmail = opp.Email__c;
        response.supervisorEmail = opp.Supervisor_User_Email__c;

        response.agreementHtml = buildDefaultAgreementHtml(opp, paymentTerms);

        response.supportingFiles = ClientAgreementAttachmentService.getSupportingFiles(opp.Id);

        return response;
    }

    @AuraEnabled
    public static Id sendAgreementToClient(
        Id opportunityId,
        String agreementHtml,
        String pdfBase64,
        List<String> separateAttachmentContentDocumentIds
    ) {
        try {
            if (opportunityId == null) {
                throw new AuraHandledException('Opportunity Id is required.');
            }

            if (String.isBlank(agreementHtml)) {
                throw new AuraHandledException('Agreement HTML is required.');
            }

            if (String.isBlank(pdfBase64)) {
                throw new AuraHandledException('PDF content is required.');
            }

            Opportunity opp = [
                SELECT Id,
                    Name,
                    Email__c,
                    Supervisor_User_Email__c,
                    Lead_Name__c,
                    RecordTypeId
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];

            validateAreliaOpportunity(opp);

            if (String.isBlank(opp.Email__c)) {
                throw new AuraHandledException(
                    'Client Email is missing on Opportunity.'
                );
            }

            if (String.isBlank(opp.Supervisor_User_Email__c)) {
                throw new AuraHandledException(
                    'Supervisor Email is missing on Opportunity.'
                );
            }

            String token = ClientAgreementTokenService.generateToken();

            Client_Agreement__c agreement = new Client_Agreement__c();
            agreement.Opportunity__c = opp.Id;
            agreement.Status__c = 'Draft';
            agreement.Agreement_HTML__c = agreementHtml;
            agreement.Token__c = token;
            agreement.Token_Expiry__c =
                ClientAgreementTokenService.getDefaultExpiry();

            insert agreement;

            ClientAgreementAttachmentService.linkSpecificSupportingFilesToAgreement(
                agreement.Id,
                separateAttachmentContentDocumentIds
            );

            String fileName =
                'Client_Agreement_' +
                agreement.Name +
                '.pdf';

            Id pdfContentVersionId =
                ClientAgreementFileService.savePdfFile(
                    fileName,
                    pdfBase64,
                    opp.Id
                );

            agreement.PDF_File_Id__c =
                String.valueOf(pdfContentVersionId);

            agreement.Status__c = 'Sent';

            update agreement;

            String signingUrl =
                System.Label.Agreement_Base_URL +
                '?id=' +
                String.valueOf(agreement.Id);

            Id owdId = ClientAgreementEmailService.getOrgWideEmailAddressIdFromLabel();

            ClientAgreementEmailService.EmailRequest emailReq =
                new ClientAgreementEmailService.EmailRequest();

            emailReq.toAddress = opp.Email__c;
            emailReq.templateDeveloperName =
                System.Label.Agreement_Email_Template;

            emailReq.orgWideEmailAddressId = owdId;

            emailReq.attachmentContentVersionId =
                pdfContentVersionId;

            emailReq.entityAttachmentContentVersionIds =
                ClientAgreementAttachmentService.getLatestContentVersionIdsByContentDocumentIds(
                    separateAttachmentContentDocumentIds
                );

            String leadName = String.isBlank(opp.Lead_Name__c)
            ? 'Client'
            : opp.Lead_Name__c.trim();
            
            emailReq.mergeValues = new Map<String, String>{
                'LEAD_NAME' => leadName,
                'SIGNING_URL' => signingUrl,
                'CLIENT_EMAIL' => opp.Email__c,
                'SUPERVISOR_EMAIL' => opp.Supervisor_User_Email__c,
                'OPPORTUNITY_NAME' => opp.Name
            };

            ClientAgreementEmailService.sendEmail(emailReq);

            return agreement.Id;

        } catch (AuraHandledException exceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                'Client Agreement handled error: ' +
                exceptionRecord.getMessage()
            );

            throw exceptionRecord;

        } catch (Exception exceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                'Client Agreement unexpected error: ' +
                exceptionRecord.getMessage()
            );

            System.debug(
                LoggingLevel.ERROR,
                'Client Agreement stack trace: ' +
                exceptionRecord.getStackTraceString()
            );

            throw new AuraHandledException(
                'Unable to send client agreement. ' +
                exceptionRecord.getMessage()
            );
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<ClientAgreementDTO.SupportingFileDTO> getOpportunitySupportingFiles(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }

        Opportunity opp = [
            SELECT Id, RecordTypeId
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        validateAreliaOpportunity(opp);

        return ClientAgreementAttachmentService.getSupportingFiles(opportunityId);
    }

    private static void validateAreliaOpportunity(Opportunity opp) {
        if (opp == null || opp.RecordTypeId == null) {
            throw new AuraHandledException('Opportunity Record Type is missing.');
        }

        Map<Id, Schema.RecordTypeInfo> recordTypeMap =
            Schema.SObjectType.Opportunity.getRecordTypeInfosById();

        Schema.RecordTypeInfo rtInfo = recordTypeMap.get(opp.RecordTypeId);

        if (rtInfo == null || rtInfo.getDeveloperName() != ARELIA_RECORD_TYPE_DEVELOPER_NAME) {
            throw new AuraHandledException('This action is available only for Arelia opportunities.');
        }
    }
    
    private static String buildDefaultAgreementHtml(
        Opportunity opp,
        List<Payment_Term__c> paymentTerms
    ) {

        // String safeOpportunityName = escapeHtml(opportunityName);
        // String safeClientEmail = escapeHtml(clientEmail);
        // String safeSupervisorEmail = escapeHtml(supervisorEmail);

        String safeOpportunityName = escapeHtml(opp.Name);
        String safeClientEmail = escapeHtml(opp.Email__c);
        String safeSupervisorEmail = escapeHtml(opp.Supervisor_User_Email__c);
        String safeClientName = escapeHtml(opp.Lead_Name__c);
        String safeClientPhone = escapeHtml(opp.Lead_Phone__c);
        String safeProjectLocation = escapeHtml(opp.Site_Location__c);
        Decimal estimatedBudget = getEstimatedBudget(opp);
        String safeEstimatedBudget = escapeHtml(formatBudget(estimatedBudget));
        String safeEstimatedProjectDuration = escapeHtml(formatProjectDuration(getEstimatedProjectDuration(opp)));

        return ''
            + '<div style="font-family: Arial, Helvetica, sans-serif; color:#222222; line-height:1.55;">'

            + '<div style="text-align:center; margin-bottom:18px;">'
            + '<div style="font-size:34px; font-weight:700; color:#1f4e79; letter-spacing:1px;">ARELIA SPACE</div>'
            + '<div style="border-top:2px solid #5b9bd5; margin:12px 0 0 0;"></div>'
            + '</div>'

            + '<h1 style="font-size:20px; color:#1f4e79; text-transform:uppercase; margin-top:24px; margin-bottom:22px;">'
            + 'Client Interior Design &amp; Turnkey Project Agreement'
            + '</h1>'

            + '<p>'
            + 'This Agreement is entered into between <strong>Arelia Space</strong> ("Company") and the Client identified '
            + 'in the Project Information section for the provision of interior design, procurement, manufacturing, '
            + 'project management, and turnkey execution services.'
            + '</p>'

            + sectionHeading('Project Information')
            + '<table style="width:100%; border-collapse:collapse; margin-top:8px; margin-bottom:24px;">'
            + projectRow('Project Name', safeOpportunityName)
            + projectRow('Client Name', safeClientName)
            + projectRow('Client Phone', safeClientPhone)
            + projectRow('Client Email', safeClientEmail)
            + projectRow('Supervisor Email', safeSupervisorEmail)
            + projectRow('Project Location', safeProjectLocation)
            + projectRow('Estimated Budget', safeEstimatedBudget)
            + projectRow('Estimated Project Duration', safeEstimatedProjectDuration)
            + '</table>'

            + numberedSection('1. Definitions',
                'Defines Client, Company, Project, Scope of Work, Change Order, Materials, Site, Completion Date, and Handover.')

            + numberedSection('2. Scope of Services',
                'Design consultation, site measurements, space planning, 2D drawings, 3D visualizations, material selection, '
                + 'BOQ preparation, procurement support, vendor coordination, custom furniture manufacturing, project supervision, '
                + 'installation, and project handover.')

            + numberedSection('3. Exclusions',
                'Structural engineering, architectural redesign, government approvals, legal permissions, HVAC redesign, utility upgrades, '
                + 'smart home systems, and any work not specifically listed in the approved proposal.')

            + sectionHeading('4. Payment Terms &amp; Conditions')
            + buildPaymentTermsHtml(paymentTerms, estimatedBudget)

            + numberedSection('5. Design Approval Process',
                'All concepts, drawings, renderings, and material selections require written approval. Upon approval, designs are considered frozen and approved for execution.')

            + numberedSection('6. Change Orders &amp; Design Modifications',
                'Any changes requested after approval shall require a Change Order detailing scope, cost impact, and timeline implications. '
                + 'No changes shall proceed without written approval.')

            + numberedSection('7. Material Selections &amp; Upgrades',
                'Material upgrades requested during execution may increase costs and extend timelines. Custom or ordered materials are non-refundable. '
                + 'Equivalent alternatives may be proposed if approved materials become unavailable.')

            + numberedSection('8. Client Responsibilities',
                'Provide site access, approvals, utilities, timely decisions, timely payments, and necessary permissions.')

            + numberedSection('9. Client Delays &amp; Indecision',
                'Failure to provide approvals within seven (7) working days may result in deemed approval. All resulting delays and costs shall be borne by the Client.')

            + numberedSection('10. Procurement &amp; Manufacturing',
                'Manufacturing and procurement commence only after receipt of required payments and approvals. Delivery dates remain subject to supplier availability.')

            + numberedSection('11. Site Conditions',
                'The Company is not responsible for hidden structural defects, concealed utilities, moisture issues, or site conditions discovered after commencement.')

            + numberedSection('12. Project Execution',
                'Execution shall be carried out according to approved drawings and specifications. Minor variations customary in construction and manufacturing shall not constitute defects.')

            + numberedSection('13. Quality Standards &amp; Tolerances',
                'Natural materials such as wood, veneer, marble, stone, and fabric may vary in color, grain, texture, and pattern. Such variations are not considered defects.')

            + numberedSection('14. Inspection &amp; Handover',
                'The Client shall inspect the project within seven (7) days of completion. Minor punch-list items shall not delay final acceptance.')

            + numberedSection('15. Warranty',
                '12-month workmanship warranty covering manufacturing and installation defects. Excludes misuse, water damage, electrical fluctuations, normal wear and tear, and third-party modifications.')

            + numberedSection('16. Intellectual Property',
                'All drawings, designs, renderings, specifications, and concepts remain the property of Arelia Space until full payment is received.')

            + numberedSection('17. Confidentiality',
                'Both parties shall maintain confidentiality regarding business and project information.')

            + numberedSection('18. Photography &amp; Marketing Rights',
                'The Company may photograph completed works for portfolio and marketing purposes while respecting Client privacy.')

            + numberedSection('19. Force Majeure',
                'Neither party shall be liable for delays caused by events beyond reasonable control including natural disasters, labour disruptions, transportation issues, governmental restrictions, or pandemics.')

            + numberedSection('20. Limitation of Liability',
                'Company liability shall not exceed the total fees paid by the Client. Indirect, consequential, and incidental damages are excluded.')

            + numberedSection('21. Termination',
                'Either party may terminate this Agreement for material breach, prolonged non-payment, insolvency, or impossibility of performance. Completed work and incurred costs remain payable.')

            + numberedSection('22. Dispute Resolution',
                'Parties shall first attempt amicable resolution. Unresolved disputes shall be referred to arbitration.')

            + numberedSection('23. Governing Law',
                'This Agreement shall be governed by the laws of the applicable jurisdiction where Arelia Space operates.')

            + numberedSection('24. Entire Agreement',
                'This document, approved quotation, BOQ, drawings, and annexures constitute the entire agreement between the parties.')

            + '<br/><br/>'
            + '<p><strong>Client Signature:</strong> Sign Below</p>'

            + '</div>';
    }

    private static String buildPaymentTermsHtml(
        List<Payment_Term__c> paymentTerms,
        Decimal estimatedBudget
    ) {
        if (paymentTerms == null || paymentTerms.isEmpty()) {
            return ''
                + '<p>No payment terms have been defined for this project.</p>';
        }

        String html = ''
            + '<p>The following payment terms shall apply to this project:</p>'
            + '<table style="width:100%; border-collapse:collapse; margin-top:10px; margin-bottom:18px;">'
            + '<tr>'
            + '<th style="width:35%; border:1px solid #cccccc; padding:8px; text-align:left; background:#f3f6fa; color:#1f4e79;">Payment Term</th>'
            + '<th style="width:15%; border:1px solid #cccccc; padding:8px; text-align:left; background:#f3f6fa; color:#1f4e79;">Percentage</th>'
            + '<th style="width:25%; border:1px solid #cccccc; padding:8px; text-align:left; background:#f3f6fa; color:#1f4e79;">Amount</th>'
            + '<th style="width:25%; border:1px solid #cccccc; padding:8px; text-align:left; background:#f3f6fa; color:#1f4e79;">Due Date</th>'
            + '</tr>';

        for (Payment_Term__c term : paymentTerms) {
            Decimal installmentAmount = calculateInstallmentAmount(
                estimatedBudget,
                term.Percentage__c
            );

            html += ''
                + '<tr>'
                + '<td style="border:1px solid #cccccc; padding:8px;">'
                + escapeHtml(term.Name)
                + '</td>'
                + '<td style="border:1px solid #cccccc; padding:8px;">'
                + escapeHtml(formatPercentage(term.Percentage__c))
                + '</td>'
                + '<td style="border:1px solid #cccccc; padding:8px;">'
                + escapeHtml(formatBudget(installmentAmount))
                + '</td>'
                + '<td style="border:1px solid #cccccc; padding:8px;">'
                + escapeHtml(formatDate(term.Due_Date__c))
                + '</td>'
                + '</tr>';
        }

        html += '</table>';

        return html;
    }

    private static Decimal calculateInstallmentAmount(
        Decimal estimatedBudget,
        Decimal percentageValue
    ) {
        if (estimatedBudget == null || percentageValue == null) {
            return null;
        }

        return (estimatedBudget * percentageValue) / 100;
    }

    private static String formatPercentage(Decimal percentageValue) {
        if (percentageValue == null) {
            return '';
        }

        Decimal scaledValue = percentageValue.setScale(2);
        String formattedValue = String.valueOf(scaledValue);

        if (formattedValue.endsWith('.00')) {
            formattedValue = formattedValue.replace('.00', '');
        } else if (formattedValue.endsWith('0')) {
            formattedValue = formattedValue.substring(0, formattedValue.length() - 1);
        }

        return formattedValue + '%';
    }

    private static String formatDate(Date dateValue) {
        if (dateValue == null) {
            return '';
        }

        return Datetime.newInstance(dateValue, Time.newInstance(0, 0, 0, 0))
            .format('dd-MMM-yyyy');
    }

    private static Decimal getEstimatedBudget(Opportunity opp) {
        if (opp == null) {
            return null;
        }

        if (opp.Re_Visit_Site_Supervisor_Estimate_Budget__c != null) {
            return opp.Re_Visit_Site_Supervisor_Estimate_Budget__c;
        }

        return opp.Supervisor_Estimated_Budget__c;
    }

    private static String getEstimatedProjectDuration(Opportunity opp) {
        if (opp == null) {
            return '';
        }

        if (!String.isBlank(opp.ReVisit_Site_Estimated_Completion_Months__c)) {
            return opp.ReVisit_Site_Estimated_Completion_Months__c;
        }

        return opp.Project_Estimated_Completion_Months__c;
    }

    private static String formatProjectDuration(String durationMonths) {
        if (String.isBlank(durationMonths)) {
            return '';
        }

        String value = durationMonths.trim();

        /*
        * If the field already stores value like "3 Months" or "1 Month",
        * do not append Month/Months again.
        */
        if (value.toLowerCase().contains('month')) {
            return value;
        }

        if (value == '1') {
            return value + ' Month';
        }

        return value + ' Months';
    }

    private static String formatBudget(Decimal budget) {
        if (budget == null) {
            return '';
        }

        return 'INR ' + String.valueOf(budget.setScale(2));
    }
    
    private static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }

        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }

    private static String sectionHeading(String heading) {
        return ''
            + '<h2 style="font-size:16px; color:#5b9bd5; text-transform:uppercase; margin-top:30px; margin-bottom:12px;">'
            + heading
            + '</h2>';
    }

    private static String numberedSection(String heading, String body) {
        return ''
            + sectionHeading(heading)
            + '<p>' + body + '</p>';
    }

    private static String projectRow(String label, String value) {
        return ''
            + '<tr>'
            + '<td style="width:32%; padding:8px;"><strong>' + label + ':</strong></td>'
            + '<td style="padding:8px;">' + value + '</td>'
            + '</tr>';
    }
}