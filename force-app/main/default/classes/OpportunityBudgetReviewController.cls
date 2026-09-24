/**
 * @description Loads and saves Opportunity budget reviews, processes approval
 * decisions, and sends budget review notification emails.
 */
@SuppressWarnings('PMD.ApexCRUDViolation, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.ApexSOQLInjection')
public without sharing class OpportunityBudgetReviewController {

    /**
     * @description Error returned when the record is not an Arelia Opportunity.
     */
    private static final String ERROR_UNSUPPORTED_RECORD_TYPE =
        'Budget review is supported only for Arelia opportunities.';

    /**
     * @description Budget review information returned to the UI.
     */
    public class BudgetReviewResponseDTO {

        /**
         * @description Opportunity associated with this budget review.
         */
        @AuraEnabled
        public Opportunity opportunity { get; set; }

        /**
         * @description Customer budget selected from the Opportunity budget fields.
         */
        @AuraEnabled
        public Decimal customerBudget { get; set; }

        /**
         * @description API name of the field supplying the customer budget.
         */
        @AuraEnabled
        public String customerBudgetSource { get; set; }

        /**
         * @description Supervisor budget, prioritizing the revisit estimate.
         */
        @AuraEnabled
        public Decimal supervisorBudget { get; set; }

        /**
         * @description API name of the field supplying the supervisor budget.
         */
        @AuraEnabled
        public String supervisorBudgetSource { get; set; }

        /**
         * @description Final budget displayed for review.
         */
        @AuraEnabled
        public Decimal finalBudget { get; set; }

        /**
         * @description Estimated project completion duration.
         */
        @AuraEnabled
        public String estimatedDuration { get; set; }

        /**
         * @description Description stored in Estimated_Budget_Description__c.
         */
        @AuraEnabled
        public String estimatedBudgetDescription { get; set; }

        /**
         * @description API name of the field supplying the estimated duration.
         */
        @AuraEnabled
        public String durationSource { get; set; }

        /**
         * @description Architecture designs associated with the Opportunity.
         */
        @AuraEnabled
        public List<ArchitectureRowDTO> architectureRows { get; set; }

        /**
         * @description Payment terms associated with the Opportunity.
         */
        @AuraEnabled
        public List<PaymentTermRowDTO> paymentTerms { get; set; }
    }

    /**
     * @description Architecture design information displayed in the budget review.
     */
    public class ArchitectureRowDTO {

        /**
         * @description Architecture design record ID.
         */
        @AuraEnabled
        public Id id { get; set; }

        /**
         * @description Architecture design record name.
         */
        @AuraEnabled
        public String name { get; set; }

        /**
         * @description Budget allocated to the architecture design.
         */
        @AuraEnabled
        public Decimal amount { get; set; }

        /**
         * @description Current client approval status.
         */
        @AuraEnabled
        public String clientApproval { get; set; }

        /**
         * @description Indicates whether the manager approved the design.
         */
        @AuraEnabled
        public Boolean managerApproval { get; set; }
    }

    /**
     * @description Payment milestone information used by the budget review.
     */
    public class PaymentTermRowDTO {

        /**
         * @description Payment term record ID.
         */
        @AuraEnabled
        public Id id { get; set; }

        /**
         * @description Display label for the payment milestone.
         */
        @AuraEnabled
        public String termLabel { get; set; }

        /**
         * @description Payment percentage expressed on a zero-to-one-hundred scale.
         */
        @AuraEnabled
        public Decimal percentage { get; set; }

        /**
         * @description Payment due date.
         */
        @AuraEnabled
        public Date dueDate { get; set; }

        /**
         * @description Indicates whether payment has been received.
         */
        @AuraEnabled
        public Boolean paymentReceived { get; set; }
    }

    /**
     * @description Client or manager decision submitted for a budget review.
     */
    public class DecisionInput {

        /**
         * @description Decision maker type, either Client or Manager.
         */
        @AuraEnabled
        public String userType { get; set; }

        /**
         * @description Requested action, with Approve indicating approval.
         */
        @AuraEnabled
        public String action { get; set; }

        /**
         * @description Remarks supplied when changes are requested.
         */
        @AuraEnabled
        public String comments { get; set; }
    }

    /**
     * @description Budget and child-record changes submitted by the UI.
     */
    public class BudgetReviewSaveRequestDTO {

        /**
         * @description Customer budget to save when supplied.
         */
        @AuraEnabled
        public Decimal inputCustomerBudget { get; set; }

        /**
         * @description Supervisor budget to save when supplied.
         */
        @AuraEnabled
        public Decimal inputSupervisorBudget { get; set; }

        /**
         * @description Estimated completion duration to save when supplied.
         */
        @AuraEnabled
        public String inputDuration { get; set; }

        /**
         * @description Description to save, or null to clear it when enabled.
         */
        @AuraEnabled
        public String inputEstimatedBudgetDescription { get; set; }

        /**
         * @description Enables updating or clearing the estimated budget description.
         */
        @AuraEnabled
        public Boolean updateEstimatedBudgetDescription { get; set; }

        /**
         * @description Architecture design budgets to update.
         */
        @AuraEnabled
        public List<ArchitectureRowDTO> architectureRows { get; set; }

        /**
         * @description Payment terms to update.
         */
        @AuraEnabled
        public List<PaymentTermRowDTO> paymentTerms { get; set; }
    }

    /**
     * @description Email recipients, template and record context for notifications.
     */
    public class EmailContext {

        /**
         * @description Primary recipient email addresses.
         */
        public List<String> toList;

        /**
         * @description Comma-separated carbon-copy email addresses.
         */
        public String ccListStr;

        /**
         * @description Developer name of the email template.
         */
        public String templateName;

        /**
         * @description Opportunity ID used in approval links.
         */
        public Id recordId;

        /**
         * @description Opportunity values used for template substitutions.
         */
        public Opportunity opp;

        /**
         * @description Approval link audience, either Client or Manager.
         */
        public String urlType;

        /**
         * @description Sets the primary email recipients.
         * @param toList Recipient email addresses.
         * @return This email context for chained configuration.
         */
        public EmailContext setToList(List<String> toList) {
            this.toList = toList;
            return this;
        }

        /**
         * @description Sets the carbon-copy email recipients.
         * @param ccListStr Comma-separated recipient email addresses.
         * @return This email context for chained configuration.
         */
        public EmailContext setCcListStr(String ccListStr) {
            this.ccListStr = ccListStr;
            return this;
        }

        /**
         * @description Sets the email template developer name.
         * @param templateName Developer name of the email template.
         * @return This email context for chained configuration.
         */
        public EmailContext setTemplateName(String templateName) {
            this.templateName = templateName;
            return this;
        }

        /**
         * @description Sets the Opportunity ID used in approval links.
         * @param recordId Opportunity record ID.
         * @return This email context for chained configuration.
         */
        public EmailContext setRecordId(Id recordId) {
            this.recordId = recordId;
            return this;
        }

        /**
         * @description Sets the Opportunity used for template substitutions.
         * @param opp Opportunity containing the required email values.
         * @return This email context for chained configuration.
         */
        public EmailContext setOpp(Opportunity opp) {
            this.opp = opp;
            return this;
        }

        /**
         * @description Sets the approval link audience.
         * @param urlType Audience identifier for the approval link.
         * @return This email context for chained configuration.
         */
        public EmailContext setUrlType(String urlType) {
            this.urlType = urlType;
            return this;
        }
    }

    /**
     * @description Loads Opportunity budget values, description and related rows.
     * @param opportunityId ID of the Arelia Opportunity to load.
     * @return Budget review response, or null when no Opportunity ID is supplied.
     */
    @AuraEnabled(cacheable=true)
    public static BudgetReviewResponseDTO getBudgetReview(
        Id opportunityId
    ) {
        if (opportunityId == null) {
            return null;
        }

        Opportunity opp = getFullOpportunity(opportunityId);

        BudgetReviewResponseDTO dto = new BudgetReviewResponseDTO();
        dto.opportunity = opp;

        // Customer budget.
        if (opp.Budget__c != null) {
            dto.customerBudget = opp.Budget__c;
            dto.customerBudgetSource = 'Budget__c';
        } else if (opp.Estimated_Budget__c != null) {
            dto.customerBudget = opp.Estimated_Budget__c;
            dto.customerBudgetSource = 'Estimated_Budget__c';
        } else {
            dto.customerBudget = null;
            dto.customerBudgetSource = 'Budget__c';
        }

        // Supervisor budget: prioritize the revisit estimate.
        if (opp.Re_Visit_Site_Supervisor_Estimate_Budget__c != null) {
            dto.supervisorBudget =
                opp.Re_Visit_Site_Supervisor_Estimate_Budget__c;

            dto.supervisorBudgetSource =
                'Re_Visit_Site_Supervisor_Estimate_Budget__c';
        } else if (opp.Supervisor_Estimated_Budget__c != null) {
            dto.supervisorBudget =
                opp.Supervisor_Estimated_Budget__c;

            dto.supervisorBudgetSource =
                'Supervisor_Estimated_Budget__c';
        } else {
            dto.supervisorBudget = null;

            dto.supervisorBudgetSource =
                'Supervisor_Estimated_Budget__c';
        }

        dto.finalBudget = dto.supervisorBudget;

        dto.estimatedBudgetDescription =
            opp.Estimated_Budget_Description__c;

        // Duration: prioritize the revisit duration.
        if (opp.ReVisit_Site_Estimated_Completion_Months__c != null) {
            dto.estimatedDuration = String.valueOf(
                opp.ReVisit_Site_Estimated_Completion_Months__c
            );

            dto.durationSource =
                'ReVisit_Site_Estimated_Completion_Months__c';
        } else if (opp.Project_Estimated_Completion_Months__c != null) {
            dto.estimatedDuration = String.valueOf(
                opp.Project_Estimated_Completion_Months__c
            );

            dto.durationSource =
                'Project_Estimated_Completion_Months__c';
        } else {
            dto.estimatedDuration = null;

            dto.durationSource =
                'Project_Estimated_Completion_Months__c';
        }

        dto.architectureRows = getArchRows(opportunityId);
        dto.paymentTerms = getPaymentTerms(opportunityId);

        return dto;
    }

    /**
     * @description Saves Opportunity budget details and associated child rows.
     * @param opportunityId ID of the Arelia Opportunity to update.
     * @param req Budget values and child-record changes to save.
     * @return Updated budget review, or null when the ID or request is missing.
     */
    @AuraEnabled
    public static BudgetReviewResponseDTO saveChildRows(
        Id opportunityId,
        BudgetReviewSaveRequestDTO req
    ) {
        if (opportunityId == null || req == null) {
            return null;
        }

        Id areliaOpportunityRecordTypeId =
            getAreliaOpportunityRecordTypeId();

        List<Opportunity> opportunitiesToUpdate = [
            SELECT
                Id,
                Budget__c,
                Estimated_Budget__c,
                Estimated_Budget_Description__c,
                Project_Request_Quotation_Type__c,
                Supervisor_Estimated_Budget__c,
                Re_Visit_Site_Supervisor_Estimate_Budget__c,
                Project_Estimated_Completion_Months__c,
                ReVisit_Site_Estimated_Completion_Months__c
            FROM Opportunity
            WHERE Id = :opportunityId
                AND RecordTypeId = :areliaOpportunityRecordTypeId
            LIMIT 1
        ];

        if (opportunitiesToUpdate.isEmpty()) {
            throw new AuraHandledException(
                ERROR_UNSUPPORTED_RECORD_TYPE
            );
        }

        Opportunity oppToUpdate = opportunitiesToUpdate[0];
        Boolean oppChanged = false;

        // Customer budget.
        if (req.inputCustomerBudget != null) {
            if (
                oppToUpdate.Project_Request_Quotation_Type__c ==
                'Manual'
            ) {
                oppToUpdate.Budget__c = req.inputCustomerBudget;
            } else if (
                oppToUpdate.Project_Request_Quotation_Type__c ==
                'Automation'
            ) {
                oppToUpdate.Estimated_Budget__c =
                    req.inputCustomerBudget;
            }

            oppChanged = true;
        }

        // Supervisor budget.
        if (req.inputSupervisorBudget != null) {
            if (
                oppToUpdate.Re_Visit_Site_Supervisor_Estimate_Budget__c
                != null
            ) {
                oppToUpdate.Re_Visit_Site_Supervisor_Estimate_Budget__c =
                    req.inputSupervisorBudget;
            } else {
                oppToUpdate.Supervisor_Estimated_Budget__c =
                    req.inputSupervisorBudget;
            }

            oppChanged = true;
        }

        // Duration.
        if (req.inputDuration != null) {
            if (
                oppToUpdate.ReVisit_Site_Estimated_Completion_Months__c
                != null
            ) {
                oppToUpdate.ReVisit_Site_Estimated_Completion_Months__c =
                    req.inputDuration;
            } else {
                oppToUpdate.Project_Estimated_Completion_Months__c =
                    req.inputDuration;
            }

            oppChanged = true;
        }

        // Explicit flag allows clearing while protecting older callers.
        if (req.updateEstimatedBudgetDescription == true) {
            oppToUpdate.Estimated_Budget_Description__c =
                req.inputEstimatedBudgetDescription;

            oppChanged = true;
        }

        if (oppChanged) {
            update oppToUpdate;
        }

        updateArchitectureRows(req.architectureRows);
        updatePaymentTerms(req.paymentTerms);

        return getBudgetReview(opportunityId);
    }

    /**
     * @description Sets the budget status to Sent for Client Approval.
     * @param recordId ID of the Opportunity being submitted.
     */
    @AuraEnabled
    public static void submitToClient(Id recordId) {
        try {
            Opportunity opp = getFullOpportunity(recordId);

            opp.Budget_Review_Status__c =
                'Sent for Client Approval';

            update opp;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Processes a client or manager budget review decision.
     * @param recordId ID of the Opportunity being reviewed.
     * @param data Decision maker, action and comments.
     */
    @AuraEnabled
    public static void submitDecision(
        Id recordId,
        DecisionInput data
    ) {
        if (recordId == null) {
            throw new AuraHandledException(
                'Error: Record ID is missing.'
            );
        }

        if (data == null) {
            throw new AuraHandledException(
                'Error: Decision Data is missing.'
            );
        }

        if (String.isBlank(data.userType)) {
            throw new AuraHandledException(
                'Error: User Type is missing.'
            );
        }

        Opportunity opp = getFullOpportunity(recordId);

        if (data.userType == 'Client') {
            handleClientDecision(opp, data);
        } else if (data.userType == 'Manager') {
            handleManagerDecision(opp, data);
        } else {
            throw new AuraHandledException(
                'Error: Invalid User Type (' + data.userType + ')'
            );
        }
    }

    /**
     * @description Applies and saves a client approval or change request.
     * @param opp Opportunity receiving the client decision.
     * @param data Client action and comments.
     */
    private static void handleClientDecision(
        Opportunity opp,
        DecisionInput data
    ) {
        if (data.action == 'Approve') {
            opp.Budget_Review_Status__c = 'Client Approved';
        } else {
            opp.Budget_Review_Status__c =
                'Client Requested Changes';

            opp.Budget_Review_Client_Remarks__c = data.comments;
        }

        safeUpdate(opp);
    }

    /**
     * @description Applies and saves a manager approval or change request.
     * @param opp Opportunity receiving the manager decision.
     * @param data Manager action and comments.
     */
    private static void handleManagerDecision(
        Opportunity opp,
        DecisionInput data
    ) {
        if (data.action == 'Approve') {
            opp.Budget_Review_Status__c = 'Manager Approved';
        } else {
            opp.Budget_Review_Status__c =
                'Manager Requested Changes';

            opp.Budget_Review_Manager_Remarks__c = data.comments;
        }

        safeUpdate(opp);
    }

    /**
     * @description Dispatches notifications for changed budget review statuses.
     * Called by the Opportunity trigger handler in an after-update context.
     * @param newOpps Updated Opportunity records.
     * @param oldMap Previous Opportunity records indexed by ID.
     */
    public static void sendBudgetReviewEmails(
        List<Opportunity> newOpps,
        Map<Id, Opportunity> oldMap
    ) {
        for (Opportunity newOpp : newOpps) {
            Opportunity oldOpp =
                oldMap == null ? null : oldMap.get(newOpp.Id);

            String oldStatus =
                oldOpp == null
                    ? null
                    : oldOpp.Budget_Review_Status__c;

            if (newOpp.Budget_Review_Status__c == oldStatus) {
                continue;
            }

            try {
                dispatchBudgetReviewEmail(
                    newOpp.Id,
                    newOpp.Budget_Review_Status__c
                );
            } catch (Exception ex) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Budget Review notification failed for ' +
                    newOpp.Id +
                    ': ' +
                    ex.getMessage()
                );
            }
        }
    }

    /**
     * @description Selects the notification routine for a budget review status.
     * @param recordId ID of the Opportunity whose status changed.
     * @param newStatus Updated budget review status.
     */
    private static void dispatchBudgetReviewEmail(
        Id recordId,
        String newStatus
    ) {
        if (newStatus == 'Sent for Client Approval') {
            sendClientApprovalRequestEmail(recordId);
        } else if (newStatus == 'Client Approved') {
            sendClientApprovedNotifications(recordId);
        } else if (newStatus == 'Manager Approved') {
            sendManagerApprovedNotifications(recordId);
        } else if (
            newStatus == 'Client Requested Changes' ||
            newStatus == 'Manager Requested Changes'
        ) {
            sendSupervisorChangeRequestedNotification(recordId);
        }
    }

    /**
     * @description Sends the client a budget approval request.
     * @param recordId ID of the Opportunity requiring client approval.
     */
    public static void sendClientApprovalRequestEmail(
        Id recordId
    ) {
        Opportunity opp = getFullOpportunity(recordId);
        String templateName;

        if (
            String.isNotBlank(
                opp.Budget_Review_Manager_Remarks__c
            )
        ) {
            templateName =
                Label.Budget_Template_Client_Manager_Revised;
        } else if (
            String.isNotBlank(
                opp.Budget_Review_Client_Remarks__c
            )
        ) {
            templateName =
                Label.Budget_Template_Client_Revised;
        } else {
            templateName =
                Label.Budget_Template_Client_Fresh;
        }

        List<String> toList = new List<String>();

        if (
            opp.Primary_Contact__r != null &&
            opp.Primary_Contact__r.Email != null
        ) {
            toList.add(opp.Primary_Contact__r.Email);
        }

        String ccList =
            Label.Arelia_Living_Management_Members;

        if (
            opp.Supervisor_User__r != null &&
            opp.Supervisor_User__r.Email != null
        ) {
            ccList += ',' + opp.Supervisor_User__r.Email;
        }

        sendEmailSafe(
            new EmailContext()
                .setToList(toList)
                .setCcListStr(ccList)
                .setTemplateName(templateName)
                .setRecordId(recordId)
                .setOpp(opp)
                .setUrlType('Client')
        );
    }

    /**
     * @description Acknowledges client approval and requests manager review.
     * @param recordId ID of the Opportunity approved by the client.
     */
    public static void sendClientApprovedNotifications(
        Id recordId
    ) {
        Opportunity opp = getFullOpportunity(recordId);

        String supervisorEmail =
            opp.Supervisor_User__r != null
                ? opp.Supervisor_User__r.Email
                : '';

        String teamEmails =
            Label.Arelia_Living_Management_Members;

        sendEmailSafe(
            new EmailContext()
                .setToList(
                    new List<String>{
                        opp.Primary_Contact__r.Email
                    }
                )
                .setTemplateName(
                    Label.Budget_Template_Client_Ack_Pending
                )
                .setRecordId(opp.Id)
                .setOpp(opp)
                .setUrlType('Client')
        );

        sendEmailSafe(
            new EmailContext()
                .setToList(new List<String>{supervisorEmail})
                .setCcListStr(teamEmails)
                .setTemplateName(
                    Label.Budget_Template_Notify_Supervisor
                )
                .setRecordId(opp.Id)
                .setOpp(opp)
        );

        Boolean isManagerRevised =
            String.isNotBlank(
                opp.Budget_Review_Manager_Remarks__c
            );

        String mgrTemplate =
            isManagerRevised
                ? Label.Budget_Template_Manager_Revised
                : Label.Budget_Template_Manager_Fresh;

        List<String> managerEmails =
            teamEmails != null
                ? teamEmails.split(',')
                : new List<String>();

        sendEmailSafe(
            new EmailContext()
                .setToList(managerEmails)
                .setTemplateName(mgrTemplate)
                .setRecordId(opp.Id)
                .setOpp(opp)
                .setUrlType('Manager')
        );
    }

    /**
     * @description Sends final approval notifications to the client and supervisor.
     * @param recordId ID of the Opportunity approved by the manager.
     */
    public static void sendManagerApprovedNotifications(
        Id recordId
    ) {
        Opportunity opp = getFullOpportunity(recordId);

        String supervisorEmail =
            opp.Supervisor_User__r != null
                ? opp.Supervisor_User__r.Email
                : '';

        String teamEmails =
            Label.Arelia_Living_Management_Members;

        sendEmailSafe(
            new EmailContext()
                .setToList(
                    new List<String>{
                        opp.Primary_Contact__r.Email
                    }
                )
                .setTemplateName(
                    Label.Budget_Template_Confirmation
                )
                .setRecordId(opp.Id)
                .setOpp(opp)
                .setUrlType('Client')
        );

        sendEmailSafe(
            new EmailContext()
                .setToList(new List<String>{supervisorEmail})
                .setCcListStr(teamEmails)
                .setTemplateName(
                    Label.Budget_Template_Notify_Supervisor
                )
                .setRecordId(opp.Id)
                .setOpp(opp)
        );
    }

    /**
     * @description Notifies the supervisor that budget changes were requested.
     * @param recordId ID of the Opportunity requiring budget changes.
     */
    public static void sendSupervisorChangeRequestedNotification(
        Id recordId
    ) {
        Opportunity opp = getFullOpportunity(recordId);

        String supervisorEmail =
            opp.Supervisor_User__r != null
                ? opp.Supervisor_User__r.Email
                : '';

        String teamEmails =
            Label.Arelia_Living_Management_Members;

        sendEmailSafe(
            new EmailContext()
                .setToList(new List<String>{supervisorEmail})
                .setCcListStr(teamEmails)
                .setTemplateName(
                    Label.Budget_Template_Notify_Supervisor
                )
                .setRecordId(opp.Id)
                .setOpp(opp)
        );
    }

    /**
     * @description Updates a record and converts failures to UI-readable exceptions.
     * @param obj Record containing the values to update.
     */
    private static void safeUpdate(SObject obj) {
        try {
            update obj;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'Update Failed: ' + e.getDmlMessage(0)
            );
        } catch (Exception e) {
            throw new AuraHandledException(
                'System Error: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Builds and sends a notification using a configured email template.
     * @param ctx Email recipients, template and Opportunity substitution values.
     */
    @SuppressWarnings('PMD.CognitiveComplexity')
    private static void sendEmailSafe(EmailContext ctx) {
        if (ctx.toList == null || ctx.toList.isEmpty()) {
            return;
        }

        List<EmailTemplate> templates = [
            SELECT Id, Subject, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :ctx.templateName
            LIMIT 1
        ];

        if (templates.isEmpty()) {
            System.debug(
                'ERROR: Template not found: ' + ctx.templateName
            );
            return;
        }

        EmailTemplate et = templates[0];
        String url = '#';

        if (ctx.urlType != null) {
            String baseUrl =
                Label.Arelia_Site_Label != null
                    ? Label.Arelia_Site_Label
                    : '';

            String pageUrl =
                Label.Budget_Review_Page_Name != null
                    ? Label.Budget_Review_Page_Name
                    : '';

            url =
                baseUrl +
                pageUrl +
                '?id=' +
                ctx.recordId +
                '&type=' +
                ctx.urlType;
        }

        Map<String, String> mapObj = new Map<String, String>{
            '{{OPPORTUNITY_NAME}}' =>
                (ctx.opp.Name != null ? ctx.opp.Name : ''),

            '{{CLIENT_NAME}}' =>
                (
                    ctx.opp.Primary_Contact__r != null
                        ? ctx.opp.Primary_Contact__r.Name
                        : 'Client'
                ),

            '{{SUPERVISOR_NAME}}' =>
                (
                    ctx.opp.Supervisor_User__r != null
                        ? ctx.opp.Supervisor_User__r.FirstName +
                          ' ' +
                          ctx.opp.Supervisor_User__r.LastName
                        : 'Supervisor'
                ),

            '{{CLIENT_REMARKS}}' =>
                (
                    ctx.opp.Budget_Review_Client_Remarks__c != null
                        ? ctx.opp.Budget_Review_Client_Remarks__c
                        : 'None'
                ),

            '{{MANAGER_REMARKS}}' =>
                (
                    ctx.opp.Budget_Review_Manager_Remarks__c != null
                        ? ctx.opp.Budget_Review_Manager_Remarks__c
                        : 'None'
                ),

            '{{STATUS}}' =>
                (
                    ctx.opp.Budget_Review_Status__c != null
                        ? ctx.opp.Budget_Review_Status__c
                        : ''
                ),

            '{{DURATION}}' =>
                (
                    ctx.opp.ReVisit_Site_Estimated_Completion_Months__c
                    != null
                        ? String.valueOf(
                            ctx.opp.ReVisit_Site_Estimated_Completion_Months__c
                        )
                        : (
                            ctx.opp.Project_Estimated_Completion_Months__c
                            != null
                                ? String.valueOf(
                                    ctx.opp.Project_Estimated_Completion_Months__c
                                )
                                : ''
                        )
                ),

            '{{FINAL_BUDGET}}' =>
                (
                    ctx.opp.Re_Visit_Site_Supervisor_Estimate_Budget__c
                    != null
                        ? String.valueOf(
                            ctx.opp.Re_Visit_Site_Supervisor_Estimate_Budget__c
                        )
                        : String.valueOf(
                            ctx.opp.Supervisor_Estimated_Budget__c
                        )
                ),

            '{{APPROVAL_LINK}}' => url
        };

        String subject = et.Subject;
        String body = et.HtmlValue;

        if (subject != null) {
            for (String key : mapObj.keySet()) {
                subject = subject.replace(
                    key,
                    mapObj.get(key)
                );
            }
        }

        if (body != null) {
            for (String key : mapObj.keySet()) {
                body = body.replace(
                    key,
                    mapObj.get(key)
                );
            }
        }

        Messaging.SingleEmailMessage mail =
            new Messaging.SingleEmailMessage();

        AreliaUtility.setOrgWideEmailAddress(
            mail,
            System.Label.Arelia_OWD
        );

        mail.setToAddresses(ctx.toList);

        if (String.isNotBlank(ctx.ccListStr)) {
            mail.setCcAddresses(ctx.ccListStr.split(','));
        }

        mail.setSubject(subject);
        mail.setHtmlBody(body);
        mail.setSaveAsActivity(false);

        try {
            Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{mail}
            );
        } catch (Exception e) {
            System.debug(
                'Email Failed: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Queries an Arelia Opportunity with budget and notification fields.
     * @param opId ID of the Opportunity to query.
     * @return Opportunity containing the required fields and related contact values.
     */
    private static Opportunity getFullOpportunity(Id opId) {
        Id areliaOpportunityRecordTypeId =
            getAreliaOpportunityRecordTypeId();

        List<Opportunity> opportunities = [
            SELECT
                Id,
                Name,
                Budget__c,
                Estimated_Budget__c,
                Estimated_Budget_Description__c,
                Budget_Review_Status__c,
                Budget_Review_Client_Remarks__c,
                Budget_Review_Manager_Remarks__c,
                Primary_Contact__r.Name,
                Primary_Contact__r.Email,
                Supervisor_User__r.FirstName,
                Supervisor_User__r.LastName,
                Supervisor_User__r.Email,
                ReVisit_Site_Estimated_Completion_Months__c,
                Project_Estimated_Completion_Months__c,
                Supervisor_Estimated_Budget__c,
                Re_Visit_Site_Supervisor_Estimate_Budget__c
            FROM Opportunity
            WHERE Id = :opId
                AND RecordTypeId = :areliaOpportunityRecordTypeId
            LIMIT 1
        ];

        if (opportunities.isEmpty()) {
            throw new AuraHandledException(
                ERROR_UNSUPPORTED_RECORD_TYPE
            );
        }

        return opportunities[0];
    }

    /**
     * @description Resolves the required Arelia Opportunity record type.
     * @return Arelia Opportunity record type ID.
     */
    private static Id getAreliaOpportunityRecordTypeId() {
        Id areliaOpportunityRecordTypeId =
            AreliaUtility.getAreliaOpportunityRecordTypeId();

        if (areliaOpportunityRecordTypeId == null) {
            throw new AuraHandledException(
                ERROR_UNSUPPORTED_RECORD_TYPE
            );
        }

        return areliaOpportunityRecordTypeId;
    }

    /**
     * @description Loads architecture designs associated with an Opportunity.
     * @param opportunityId ID of the parent Opportunity.
     * @return Architecture design rows ordered by creation date.
     */
    private static List<ArchitectureRowDTO> getArchRows(
        Id opportunityId
    ) {
        List<ArchitectureRowDTO> rows =
            new List<ArchitectureRowDTO>();

        String soql =
            'SELECT Id, Name, Architecture_Budget__c, ' +
            'Status__c, Manager_Approval__c ' +
            'FROM Architecture_Design__c ' +
            'WHERE Opportunity__c = :opportunityId ' +
            'ORDER BY CreatedDate ASC';

        for (SObject s : Database.query(soql)) {
            ArchitectureRowDTO r = new ArchitectureRowDTO();

            r.id = (Id)s.get('Id');
            r.name = (String)s.get('Name');
            r.amount = (Decimal)s.get('Architecture_Budget__c');
            r.clientApproval = (String)s.get('Status__c');
            r.managerApproval =
                (Boolean)s.get('Manager_Approval__c');

            rows.add(r);
        }

        return rows;
    }

    /**
     * @description Loads payment terms associated with an Opportunity.
     * @param opportunityId ID of the parent Opportunity.
     * @return Payment terms ordered by due date and creation date.
     */
    private static List<PaymentTermRowDTO> getPaymentTerms(
        Id opportunityId
    ) {
        List<PaymentTermRowDTO> rows =
            new List<PaymentTermRowDTO>();

        String soql =
            'SELECT Id, Term_Label__c, Percentage__c, ' +
            'Due_Date__c, Payment_Received__c ' +
            'FROM Payment_Term__c ' +
            'WHERE Opportunity__c = :opportunityId ' +
            'ORDER BY Due_Date__c ASC NULLS LAST, CreatedDate ASC';

        for (SObject s : Database.query(soql)) {
            PaymentTermRowDTO p = new PaymentTermRowDTO();

            p.id = (Id)s.get('Id');
            p.termLabel = (String)s.get('Term_Label__c');
            p.percentage = (Decimal)s.get('Percentage__c');
            p.dueDate = (Date)s.get('Due_Date__c');
            p.paymentReceived =
                (Boolean)s.get('Payment_Received__c');

            rows.add(p);
        }

        return rows;
    }

    /**
     * @description Updates architecture budgets using one bulk DML statement.
     * @param rows Architecture design IDs and budget values to save.
     */
    private static void updateArchitectureRows(
        List<ArchitectureRowDTO> rows
    ) {
        if (rows == null || rows.isEmpty()) {
            return;
        }

        List<Architecture_Design__c> updates =
            new List<Architecture_Design__c>();

        for (ArchitectureRowDTO r : rows) {
            if (r.id != null) {
                updates.add(
                    new Architecture_Design__c(
                        Id = r.id,
                        Architecture_Budget__c = r.amount
                    )
                );
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }

    /**
     * @description Updates supplied payment term values using one bulk DML statement.
     * @param rows Payment term IDs and field values to save.
     */
    @SuppressWarnings('PMD.CognitiveComplexity')
    private static void updatePaymentTerms(
        List<PaymentTermRowDTO> rows
    ) {
        if (rows == null || rows.isEmpty()) {
            return;
        }

        List<Payment_Term__c> updates =
            new List<Payment_Term__c>();

        for (PaymentTermRowDTO p : rows) {
            if (p.id != null) {
                Payment_Term__c paymentTerm =
                    new Payment_Term__c(Id = p.id);

                if (p.termLabel != null) {
                    paymentTerm.Term_Label__c = p.termLabel;
                }

                if (p.percentage != null) {
                    paymentTerm.Percentage__c = p.percentage;
                }

                if (p.dueDate != null) {
                    paymentTerm.Due_Date__c = p.dueDate;
                }

                if (p.paymentReceived != null) {
                    paymentTerm.Payment_Received__c =
                        p.paymentReceived;
                }

                updates.add(paymentTerm);
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }
}