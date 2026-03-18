@SuppressWarnings('PMD.ApexCRUDViolation, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.ApexSOQLInjection')
public without sharing class OpportunityBudgetReviewController {

    // --- WRAPPERS ---
    public class BudgetReviewResponseDTO {
        @AuraEnabled public Opportunity opportunity { get; set; }
        @AuraEnabled public Decimal customerBudget { get; set; }
        @AuraEnabled public String customerBudgetSource { get; set; }
        @AuraEnabled public Decimal supervisorBudget { get; set; }
        @AuraEnabled public String supervisorBudgetSource { get; set; }
        @AuraEnabled public Decimal finalBudget { get; set; }
        @AuraEnabled public String estimatedDuration { get; set; }
        @AuraEnabled public String durationSource { get; set; }
        @AuraEnabled public List<ArchitectureRowDTO> architectureRows { get; set; }
        @AuraEnabled public List<PaymentTermRowDTO> paymentTerms { get; set; }
    }

    public class ArchitectureRowDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String clientApproval { get; set; }
        @AuraEnabled public Boolean managerApproval { get; set; }
    }

    public class PaymentTermRowDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String termLabel { get; set; }
        @AuraEnabled public Decimal percentage { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
        @AuraEnabled public Boolean paymentReceived { get; set; }
    }

    public class DecisionInput {
        @AuraEnabled public String userType { get; set; }
        @AuraEnabled public String action { get; set; }
        @AuraEnabled public String comments { get; set; }
    }

    public class BudgetReviewSaveRequestDTO {
        @AuraEnabled public Decimal inputCustomerBudget { get; set; }
        @AuraEnabled public Decimal inputSupervisorBudget { get; set; }
        @AuraEnabled public String inputDuration { get; set; } 
        
        @AuraEnabled public List<ArchitectureRowDTO> architectureRows { get; set; }
        @AuraEnabled public List<PaymentTermRowDTO> paymentTerms { get; set; }
    }

    // --- EMAIL WRAPPER ---
    public class EmailContext {
        public List<String> toList;
        public String ccListStr;
        public String templateName;
        public Id recordId;
        public Opportunity opp;
        public String urlType;
        
        public EmailContext setToList(List<String> toList) { this.toList = toList; return this; }
        public EmailContext setCcListStr(String ccListStr) { this.ccListStr = ccListStr; return this; }
        public EmailContext setTemplateName(String templateName) { this.templateName = templateName; return this; }
        public EmailContext setRecordId(Id recordId) { this.recordId = recordId; return this; }
        public EmailContext setOpp(Opportunity opp) { this.opp = opp; return this; }
        public EmailContext setUrlType(String urlType) { this.urlType = urlType; return this; }
    }

    // --- 1. GET DATA ---
    @AuraEnabled(cacheable=true)
    public static BudgetReviewResponseDTO getBudgetReview(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }
        
        Opportunity opp = getFullOpportunity(opportunityId);
        BudgetReviewResponseDTO dto = new BudgetReviewResponseDTO();
        dto.opportunity = opp;
        
        // 1. CUSTOMER BUDGET
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

        // 2. SUPERVISOR BUDGET (Check Re-Visit First)
        if (opp.Re_Visit_Site_Supervisor_Estimate_Budget__c != null) {
            dto.supervisorBudget = opp.Re_Visit_Site_Supervisor_Estimate_Budget__c;
            dto.supervisorBudgetSource = 'Re_Visit_Site_Supervisor_Estimate_Budget__c';
        } else if (opp.Supervisor_Estimated_Budget__c != null) {
            dto.supervisorBudget = opp.Supervisor_Estimated_Budget__c;
            dto.supervisorBudgetSource = 'Supervisor_Estimated_Budget__c';
        } else {
            dto.supervisorBudget = null;
            dto.supervisorBudgetSource = 'Supervisor_Estimated_Budget__c';
        }
        
        dto.finalBudget = dto.supervisorBudget; 

        // 3. DURATION (Check Re-Visit First)
        if (opp.ReVisit_Site_Estimated_Completion_Months__c != null) {
            dto.estimatedDuration = String.valueOf(opp.ReVisit_Site_Estimated_Completion_Months__c);
            dto.durationSource = 'ReVisit_Site_Estimated_Completion_Months__c';
        } else if (opp.Project_Estimated_Completion_Months__c != null) {
            dto.estimatedDuration = String.valueOf(opp.Project_Estimated_Completion_Months__c);
            dto.durationSource = 'Project_Estimated_Completion_Months__c';
        } else {
            dto.estimatedDuration = null;
            dto.durationSource = 'Project_Estimated_Completion_Months__c';
        }

        dto.architectureRows = getArchRows(opportunityId);
        dto.paymentTerms = getPaymentTerms(opportunityId);
        
        return dto;
    }

    // --- 2. SAVE (Consolidated Logic) ---
    @AuraEnabled
    public static BudgetReviewResponseDTO saveChildRows(Id opportunityId, BudgetReviewSaveRequestDTO req) {
        if (opportunityId == null || req == null) {
            return null;
        }
        
        Opportunity oppToUpdate = [SELECT Id, 
                                   Budget__c,
                                   Estimated_Budget__c,
                                   Project_Request_Quotation_Type__c, 
                                   Supervisor_Estimated_Budget__c,
                                   Re_Visit_Site_Supervisor_Estimate_Budget__c, 
                                   Project_Estimated_Completion_Months__c,
                                   ReVisit_Site_Estimated_Completion_Months__c 
                                   FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
        
        Boolean oppChanged = false;

        // ==============================================================
        // FIX: Evaluates using your exact API Names (Manual / Automation)
        // ==============================================================
        if (req.inputCustomerBudget != null) {
            if (oppToUpdate.Project_Request_Quotation_Type__c == 'Manual') {
                oppToUpdate.Budget__c = req.inputCustomerBudget;
            } else if (oppToUpdate.Project_Request_Quotation_Type__c == 'Automation') {
                oppToUpdate.Estimated_Budget__c = req.inputCustomerBudget;
            }
            oppChanged = true;
        }

        // Supervisor Budget
        if (req.inputSupervisorBudget != null) {
            if (oppToUpdate.Re_Visit_Site_Supervisor_Estimate_Budget__c != null) {
                oppToUpdate.Re_Visit_Site_Supervisor_Estimate_Budget__c = req.inputSupervisorBudget;
            } else {
                oppToUpdate.Supervisor_Estimated_Budget__c = req.inputSupervisorBudget;
            }
            oppChanged = true;
        }

        // Duration
        if (req.inputDuration != null) { 
            if (oppToUpdate.ReVisit_Site_Estimated_Completion_Months__c != null) {
                oppToUpdate.ReVisit_Site_Estimated_Completion_Months__c = req.inputDuration;
            } else {
                oppToUpdate.Project_Estimated_Completion_Months__c = req.inputDuration;
            }
            oppChanged = true;
        }

        if (oppChanged) {
            update oppToUpdate;
        }

        updateArchitectureRows(req.architectureRows);
        updatePaymentTerms(req.paymentTerms);
        
        return getBudgetReview(opportunityId);
    }

    // --- 3. SUBMIT TO CLIENT ---
    @AuraEnabled
    public static void submitToClient(Id recordId) {
        try {
            Opportunity opp = getFullOpportunity(recordId);
            opp.Budget_Review_Status__c = 'Sent for Client Approval';
            update opp;

            String templateName;
            
            if (String.isNotBlank(opp.Budget_Review_Manager_Remarks__c)) {
                 templateName = Label.Budget_Template_Client_Manager_Revised;
            } else if (String.isNotBlank(opp.Budget_Review_Client_Remarks__c)) {
                 templateName = Label.Budget_Template_Client_Revised;
            } else {
                 templateName = Label.Budget_Template_Client_Fresh;
            }

            List<String> toList = new List<String>();
            if (opp.Primary_Contact__r != null && opp.Primary_Contact__r.Email != null) {
                toList.add(opp.Primary_Contact__r.Email);
            }
            
            String ccList = Label.Arelia_Living_Enrollment_Members;
            if (opp.Supervisor_User__r != null && opp.Supervisor_User__r.Email != null) {
                ccList += ',' + opp.Supervisor_User__r.Email;
            }

            sendEmailSafe(new EmailContext()
                .setToList(toList)
                .setCcListStr(ccList)
                .setTemplateName(templateName)
                .setRecordId(recordId)
                .setOpp(opp)
                .setUrlType('Client'));

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // --- 4. SUBMIT DECISION ---
    @AuraEnabled
    public static void submitDecision(Id recordId, DecisionInput data) {
        if (recordId == null) {
            throw new AuraHandledException('Error: Record ID is missing.');
        }
        if (data == null) {
            throw new AuraHandledException('Error: Decision Data is missing.');
        }
        if (String.isBlank(data.userType)) {
            throw new AuraHandledException('Error: User Type is missing.');
        }

        Opportunity opp = getFullOpportunity(recordId);
        
        if (data.userType == 'Client') {
            handleClientDecision(opp, data);
        } else if (data.userType == 'Manager') {
            handleManagerDecision(opp, data);
        } else {
            throw new AuraHandledException('Error: Invalid User Type (' + data.userType + ')');
        }
    }

    // --- HELPERS ---
    
    private static void handleClientDecision(Opportunity opp, DecisionInput data) {
        String supervisorEmail = (opp.Supervisor_User__r != null) ? opp.Supervisor_User__r.Email : '';
        String teamEmails = Label.Arelia_Living_Enrollment_Members;

        if (data.action == 'Approve') {
            opp.Budget_Review_Status__c = 'Client Approved';
            safeUpdate(opp); 
            
            sendEmailSafe(new EmailContext()
                .setToList(new List<String>{opp.Primary_Contact__r.Email})
                .setTemplateName(Label.Budget_Template_Client_Ack_Pending)
                .setRecordId(opp.Id)
                .setOpp(opp)
                .setUrlType('Client'));
            
            sendEmailSafe(new EmailContext()
                .setToList(new List<String>{supervisorEmail})
                .setCcListStr(teamEmails)
                .setTemplateName(Label.Budget_Template_Notify_Supervisor)
                .setRecordId(opp.Id)
                .setOpp(opp));

            Boolean isManagerRevised = String.isNotBlank(opp.Budget_Review_Manager_Remarks__c);
            String mgrTemplate = isManagerRevised ? Label.Budget_Template_Manager_Revised : Label.Budget_Template_Manager_Fresh;
            List<String> managerEmails = (teamEmails != null) ? teamEmails.split(',') : new List<String>();
            
            sendEmailSafe(new EmailContext()
                .setToList(managerEmails)
                .setTemplateName(mgrTemplate)
                .setRecordId(opp.Id)
                .setOpp(opp)
                .setUrlType('Manager'));

        } else {
            opp.Budget_Review_Status__c = 'Client Requested Changes';
            opp.Budget_Review_Client_Remarks__c = data.comments; 
            safeUpdate(opp);
            
            sendEmailSafe(new EmailContext()
                .setToList(new List<String>{supervisorEmail})
                .setCcListStr(teamEmails)
                .setTemplateName(Label.Budget_Template_Notify_Supervisor)
                .setRecordId(opp.Id)
                .setOpp(opp));
        }
    }

    private static void handleManagerDecision(Opportunity opp, DecisionInput data) {
        String supervisorEmail = (opp.Supervisor_User__r != null) ? opp.Supervisor_User__r.Email : '';
        String teamEmails = Label.Arelia_Living_Enrollment_Members;

        if (data.action == 'Approve') {
            opp.Budget_Review_Status__c = 'Manager Approved';
            safeUpdate(opp);
            
            sendEmailSafe(new EmailContext()
                .setToList(new List<String>{opp.Primary_Contact__r.Email})
                .setTemplateName(Label.Budget_Template_Confirmation)
                .setRecordId(opp.Id)
                .setOpp(opp)
                .setUrlType('Client'));

            sendEmailSafe(new EmailContext()
                .setToList(new List<String>{supervisorEmail})
                .setCcListStr(teamEmails)
                .setTemplateName(Label.Budget_Template_Notify_Supervisor)
                .setRecordId(opp.Id)
                .setOpp(opp));
        } else {
            opp.Budget_Review_Status__c = 'Manager Requested Changes';
            opp.Budget_Review_Manager_Remarks__c = data.comments;
            safeUpdate(opp);
            
            sendEmailSafe(new EmailContext()
                .setToList(new List<String>{supervisorEmail})
                .setCcListStr(teamEmails)
                .setTemplateName(Label.Budget_Template_Notify_Supervisor)
                .setRecordId(opp.Id)
                .setOpp(opp));
        }
    }
    
    private static void safeUpdate(SObject obj) {
        try {
            update obj;
        } catch (DmlException e) {
            throw new AuraHandledException('Update Failed: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('System Error: ' + e.getMessage());
        }
    }

    @SuppressWarnings('PMD.CognitiveComplexity')
    private static void sendEmailSafe(EmailContext ctx) {
        if (ctx.toList == null || ctx.toList.isEmpty()) {
            return;
        }
        List<EmailTemplate> templates = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :ctx.templateName LIMIT 1];
        if (templates.isEmpty()) {
            System.debug('ERROR: Template not found: ' + ctx.templateName);
            return;
        }
        EmailTemplate et = templates[0];
        OrgWideEmailAddress owea = null;
        
        if (String.isNotBlank(Label.Arelia_OWD)) {
             List<OrgWideEmailAddress> oweas = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :Label.Arelia_OWD LIMIT 1];
             if (!oweas.isEmpty()) {
                 owea = oweas[0];
             }
        }
        
        String url = '#';
        if (ctx.urlType != null) {
            String baseUrl = (Label.Arelia_Site_Label != null) ? Label.Arelia_Site_Label : '';
            String pageUrl = (Label.Budget_Review_Page_Name != null) ? Label.Budget_Review_Page_Name : '';
            url = baseUrl + pageUrl + '?id=' + ctx.recordId + '&type=' + ctx.urlType;
        }
        
        Map<String, String> mapObj = new Map<String, String>{
            '{{OPPORTUNITY_NAME}}' => (ctx.opp.Name != null ? ctx.opp.Name : ''),
            '{{CLIENT_NAME}}' => (ctx.opp.Primary_Contact__r != null ? ctx.opp.Primary_Contact__r.Name : 'Client'),
            '{{SUPERVISOR_NAME}}' => (ctx.opp.Supervisor_User__r != null ? ctx.opp.Supervisor_User__r.FirstName + ' ' + ctx.opp.Supervisor_User__r.LastName : 'Supervisor'),
            '{{CLIENT_REMARKS}}' => (ctx.opp.Budget_Review_Client_Remarks__c != null ? ctx.opp.Budget_Review_Client_Remarks__c : 'None'),
            '{{MANAGER_REMARKS}}' => (ctx.opp.Budget_Review_Manager_Remarks__c != null ? ctx.opp.Budget_Review_Manager_Remarks__c : 'None'),
            '{{STATUS}}' => (ctx.opp.Budget_Review_Status__c != null ? ctx.opp.Budget_Review_Status__c : ''),
            '{{DURATION}}' => (ctx.opp.ReVisit_Site_Estimated_Completion_Months__c != null ? String.valueOf(ctx.opp.ReVisit_Site_Estimated_Completion_Months__c) : (ctx.opp.Project_Estimated_Completion_Months__c != null ? String.valueOf(ctx.opp.Project_Estimated_Completion_Months__c) : '')),
            '{{FINAL_BUDGET}}' => (ctx.opp.Re_Visit_Site_Supervisor_Estimate_Budget__c != null ? String.valueOf(ctx.opp.Re_Visit_Site_Supervisor_Estimate_Budget__c) : String.valueOf(ctx.opp.Supervisor_Estimated_Budget__c)),
            '{{APPROVAL_LINK}}' => url
        };
        
        String subject = et.Subject;
        String body = et.HtmlValue;
        
        if (subject != null) {
            for (String key : mapObj.keySet()) {
                subject = subject.replace(key, mapObj.get(key));
            }
        }
        if (body != null) {
            for (String key : mapObj.keySet()) {
                body = body.replace(key, mapObj.get(key));
            }
        }
        
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        if (owea != null) {
            mail.setOrgWideEmailAddressId(owea.Id);
        }
        mail.setToAddresses(ctx.toList);
        
        if (String.isNotBlank(ctx.ccListStr)) {
            mail.setCcAddresses(ctx.ccListStr.split(','));
        }
        mail.setSubject(subject);
        mail.setHtmlBody(body);
        mail.setSaveAsActivity(false);
        
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{mail});
        } catch (Exception e) {
            System.debug('Email Failed: ' + e.getMessage());
        }
    }

    private static Opportunity getFullOpportunity(Id opId) {
        return [SELECT Id, Name, Budget__c, Estimated_Budget__c, 
                Budget_Review_Status__c, Budget_Review_Client_Remarks__c, Budget_Review_Manager_Remarks__c,
                Primary_Contact__r.Name, Primary_Contact__r.Email,
                Supervisor_User__r.FirstName, Supervisor_User__r.LastName, Supervisor_User__r.Email,
                ReVisit_Site_Estimated_Completion_Months__c, Project_Estimated_Completion_Months__c,
                Supervisor_Estimated_Budget__c, Re_Visit_Site_Supervisor_Estimate_Budget__c
                FROM Opportunity WHERE Id = :opId];
    }

    private static List<ArchitectureRowDTO> getArchRows(Id opportunityId) {
        List<ArchitectureRowDTO> rows = new List<ArchitectureRowDTO>();
        String soql = 'SELECT Id, Name, Architecture_Budget__c, Status__c, Manager_Approval__c FROM Architecture_Design__c WHERE Opportunity__c = :opportunityId ORDER BY CreatedDate ASC';
        for (SObject s : Database.query(soql)) {
            ArchitectureRowDTO r = new ArchitectureRowDTO();
            r.id = (Id)s.get('Id');
            r.name = (String)s.get('Name');
            r.amount = (Decimal)s.get('Architecture_Budget__c');
            r.clientApproval = (String)s.get('Status__c'); 
            r.managerApproval = (Boolean)s.get('Manager_Approval__c'); 
            rows.add(r);
        }
        return rows;
    }

    private static List<PaymentTermRowDTO> getPaymentTerms(Id opportunityId) {
        List<PaymentTermRowDTO> rows = new List<PaymentTermRowDTO>();
        String soql = 'SELECT Id, Term_Label__c, Percentage__c, Due_Date__c, Payment_Received__c FROM Payment_Term__c WHERE Opportunity__c = :opportunityId ORDER BY Due_Date__c ASC NULLS LAST, CreatedDate ASC';
        for (SObject s : Database.query(soql)) {
            PaymentTermRowDTO p = new PaymentTermRowDTO();
            p.id = (Id)s.get('Id');
            p.termLabel = (String)s.get('Term_Label__c');
            p.percentage = (Decimal)s.get('Percentage__c');
            p.dueDate = (Date)s.get('Due_Date__c');
            p.paymentReceived = (Boolean)s.get('Payment_Received__c');
            rows.add(p);
        }
        return rows;
    }
    
    private static void updateArchitectureRows(List<ArchitectureRowDTO> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        List<SObject> updates = new List<SObject>();
        for (ArchitectureRowDTO r : rows) {
            if (r.id != null) {
                SObject s = Schema.getGlobalDescribe().get('Architecture_Design__c').newSObject();
                s.put('Id', r.id);
                s.put('Architecture_Budget__c', r.amount);
                updates.add(s);
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    @SuppressWarnings('PMD.CognitiveComplexity')
    private static void updatePaymentTerms(List<PaymentTermRowDTO> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        List<SObject> updates = new List<SObject>();
        for (PaymentTermRowDTO p : rows) {
            if (p.id != null) {
                SObject s = Schema.getGlobalDescribe().get('Payment_Term__c').newSObject();
                s.put('Id', p.id);
                if (p.termLabel != null) {
                    s.put('Term_Label__c', p.termLabel);
                }
                if (p.percentage != null) {
                    s.put('Percentage__c', p.percentage);
                }
                if (p.dueDate != null) {
                    s.put('Due_Date__c', p.dueDate);
                }
                if (p.paymentReceived != null) {
                    s.put('Payment_Received__c', p.paymentReceived);
                }
                updates.add(s);
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }
}