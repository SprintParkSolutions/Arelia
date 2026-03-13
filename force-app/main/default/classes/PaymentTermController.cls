@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class PaymentTermController {

    // --- WRAPPERS ---
    public class DecisionInput {
        @AuraEnabled public String userType { get; set; }
        @AuraEnabled public String action { get; set; }
        @AuraEnabled public String comments { get; set; }
    }

    public class ParentInfo {
        public String name;
        public String primaryContactName;
        public String primaryContactPhone;
        public String primaryContactEmail;
        public String supervisorName;
        public String supervisorEmail;
        public String status;
        public String managerRemarks;
        public String clientRemarks;
    }

    public class EmailRequest {
        public String templateName;
        public List<String> toList;
        public List<String> ccList;
        public Id recordId;
        public ParentInfo info;
        public String urlUserType; // NEW: Explicitly define link type (Manager/Client)
    }

    // =========================================================================
    // 1. PUBLIC API
    // =========================================================================
    
    @AuraEnabled
    public static Map<String, Object> getPaymentTerms(Id recordId) {
        if (recordId == null) { return null; }
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        return new Map<String, Object>{
            'opportunity' => fetchParentRecord(recordId, sObjName),
            'terms' => fetchTerms(recordId, sObjName),
            'objectType' => sObjName
        };
    }

    @AuraEnabled
    public static void savePaymentTerms(List<Payment_Term__c> terms, Id recordId, List<Id> termsToDelete) {
        try {
            executeSaveLogic(terms, recordId, termsToDelete);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void submitToManager(Id recordId) {
        try {
            executeSubmitToManager(recordId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> getApprovalData(Id recordId) {
        return getPaymentTerms(recordId);
    }

    @AuraEnabled
    public static void submitDecision(Id recordId, DecisionInput data) {
        try {
            if (data == null) { throw new AuraHandledException('Decision data is missing.'); }
            executeSubmitDecision(recordId, data);
        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }

    // =========================================================================
    // 2. BUSINESS LOGIC HANDLERS
    // =========================================================================

    private static void executeSaveLogic(List<Payment_Term__c> terms, Id recordId, List<Id> termsToDelete) {
        if (termsToDelete != null && !termsToDelete.isEmpty()) {
            delete [SELECT Id FROM Payment_Term__c WHERE Id IN :termsToDelete];
        }
        if (terms == null || terms.isEmpty()) { return; }
        
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        for (Payment_Term__c term : terms) {
            if (sObjName == 'Opportunity') { term.Opportunity__c = recordId; } 
            else if (sObjName == 'Project__c') { term.Project__c = recordId; }

            if (String.isNotBlank(term.Term_Label__c)) { term.Name = term.Term_Label__c; }
        }
        upsert terms;
    }

    private static void executeSubmitToManager(Id recordId) {
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Project__c') { return; } 

        SObject parent = fetchParentRecord(recordId, sObjName);
        parent.put('Payment_Terms_Status__c', 'Sent for Manager Approval');
        update parent;

        sendSubmissionEmail(parent, recordId);
    }

    private static void executeSubmitDecision(Id recordId, DecisionInput data) {
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Project__c') { return; } 

        updateStatusDecision(recordId, data, sObjName);
        
        ParentInfo info = getParentInfo(recordId);
        if (data.userType == 'Manager') {
            processManagerAction(data, info, recordId);
        } else if (data.userType == 'Client') {
            processClientAction(data, info, recordId);
        }
    }

    private static void updateStatusDecision(Id recordId, DecisionInput data, String sObjName) {
        SObject parent = fetchParentRecord(recordId, sObjName);

        if (data.userType == 'Manager') {
            parent.put('Payment_Terms_Status__c', (data.action == 'Approve') ? 'Sent for Client Approval' : 'Manager Requested Changes');
            if (data.action == 'Reject') {
                parent.put('Payment_Term_Manager_Remarks__c', data.comments);
            } 
        } else if (data.userType == 'Client') {
            parent.put('Payment_Terms_Status__c', (data.action == 'Approve') ? 'Client Approved' : 'Client Requested Changes');
            if (data.action == 'Reject') {
                parent.put('Payment_Term_Client_Remarks__c', data.comments);
            }
        }
        update parent;
    }

    // =========================================================================
    // 3. DATA FETCHING 
    // =========================================================================
    
    private static SObject fetchParentRecord(Id recordId, String sObjName) {
        if (sObjName == 'Opportunity') {
            return [SELECT Id, Name, Payment_Terms_Status__c, 
                    Payment_Term_Manager_Remarks__c, Payment_Term_Client_Remarks__c 
                    FROM Opportunity WHERE Id = :recordId LIMIT 1];
        } 
        if (sObjName == 'Project__c') {
            return Database.query('SELECT Id, Name FROM Project__c WHERE Id = :recordId LIMIT 1');
        }
        return null;
    }

    private static List<Payment_Term__c> fetchTerms(Id recordId, String sObjName) {
        if (sObjName == 'Opportunity') {
            return [SELECT Id, Name, Term_Label__c, Percentage__c, Due_Date__c, Payment_Received__c 
                    FROM Payment_Term__c WHERE Opportunity__c = :recordId ORDER BY Due_Date__c ASC];
        } 
        if (sObjName == 'Project__c') {
            return [SELECT Id, Name, Term_Label__c, Percentage__c, Due_Date__c, Payment_Received__c 
                    FROM Payment_Term__c WHERE Project__c = :recordId ORDER BY Due_Date__c ASC];
        }
        return new List<Payment_Term__c>();
    }

    private static ParentInfo getParentInfo(Id recordId) {
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Opportunity') {
            return getOpportunityInfo(recordId);
        } else if (sObjName == 'Project__c') {
            return getProjectInfo(recordId);
        }
        return new ParentInfo();
    }

    private static ParentInfo getOpportunityInfo(Id recordId) {
        ParentInfo info = new ParentInfo();
        Opportunity opp = [SELECT Name, Primary_Contact__r.Name, Primary_Contact__r.Phone, Primary_Contact__r.Email, 
                           Supervisor_User__r.FirstName, Supervisor_User__r.LastName, Supervisor_User__r.Email,
                           Payment_Terms_Status__c, Payment_Term_Manager_Remarks__c, Payment_Term_Client_Remarks__c, Supervisor_Name__c
                           FROM Opportunity WHERE Id = :recordId LIMIT 1];
        info.name = opp.Name;
        info.status = opp.Payment_Terms_Status__c;
        info.managerRemarks = opp.Payment_Term_Manager_Remarks__c;
        info.clientRemarks = opp.Payment_Term_Client_Remarks__c;
        extractContactInfo(info, opp);
        return info;
    }

    private static ParentInfo getProjectInfo(Id recordId) {
        ParentInfo info = new ParentInfo();
        SObject proj = Database.query('SELECT Name FROM Project__c WHERE Id = :recordId LIMIT 1');
        info.name = (String) proj.get('Name');
        return info; 
    }

    private static void extractContactInfo(ParentInfo info, SObject record) {
        try {
            SObject contact = record.getSObject('Primary_Contact__r');
            if (contact != null) {
                info.primaryContactName = (String) contact.get('Name');
                info.primaryContactPhone = (String) contact.get('Phone');
                info.primaryContactEmail = (String) contact.get('Email');
            }
        } catch (Exception e) { /* Field missing */ }
        
        try {
            SObject supervisor = record.getSObject('Supervisor_User__r');
            String fName = '', lName = '', sEmail = '';
            if (supervisor != null) {
                fName = (String) supervisor.get('FirstName');
                lName = (String) supervisor.get('LastName');
                sEmail = (String) supervisor.get('Email');
            }
            String fallbackName = '';
            try { fallbackName = (String) record.get('Supervisor_Name__c'); } catch(Exception e) {}
            
            info.supervisorEmail = sEmail;
            info.supervisorName = formatName(fName, lName, fallbackName);
        } catch (Exception e) { /* Field missing */ }
    }

    private static String formatName(String fName, String lName, String fallback) {
        String name = ((fName != null ? fName : '') + ' ' + (lName != null ? lName : '')).trim();
        return String.isNotBlank(name) ? name : fallback;
    }

    // =========================================================================
    // 4. EMAIL LOGIC 
    // =========================================================================

    private static void sendSubmissionEmail(SObject parent, Id recordId) {
        String clientRemarks = (String) parent.get('Payment_Term_Client_Remarks__c');
        String managerRemarks = (String) parent.get('Payment_Term_Manager_Remarks__c');
        
        String tpl = Label.Payment_Term_Template_Manager; 
        if (String.isNotBlank(clientRemarks)) {
            tpl = Label.Payment_Term_Template_Manager_Client_Revised;
        } else if (String.isNotBlank(managerRemarks)) {
            tpl = Label.Payment_Term_Template_Manager_Revised;
        }

        EmailRequest req = new EmailRequest();
        req.toList = safeSplit(Label.Arelia_Living_Enrollment_Members);
        req.templateName = tpl;
        req.recordId = recordId;
        req.info = getParentInfo(recordId);
        
        // FIX: Explicitly set URL type to Manager
        req.urlUserType = 'Manager';
        
        sendEmailGeneric(req);
    }

    private static void processManagerAction(DecisionInput data, ParentInfo info, Id recordId) {
        if (data.action == 'Reject') {
            notifySupervisor(info, recordId);
        } else {
            sendClientApprovalRequest(info, recordId);
            notifySupervisor(info, recordId);
        }
    }

    private static void processClientAction(DecisionInput data, ParentInfo info, Id recordId) {
        if (data.action == 'Reject') {
            notifySupervisor(info, recordId);
        } else {
            sendClientConfirmation(info, recordId);
            notifySupervisor(info, recordId);
        }
    }

    private static void sendClientApprovalRequest(ParentInfo info, Id recordId) {
        if (String.isBlank(info.primaryContactEmail)) { return; }
        
        EmailRequest req = new EmailRequest();
        req.toList = new List<String>{info.primaryContactEmail};
        req.templateName = String.isNotBlank(info.clientRemarks) ? Label.Payment_Term_Template_Client_Revised : Label.Payment_Term_Template_Client;
        req.recordId = recordId;
        req.info = info;
        
        // FIX: Explicitly set URL type to Client
        req.urlUserType = 'Client';
        
        sendEmailGeneric(req);
    }

    private static void sendClientConfirmation(ParentInfo info, Id recordId) {
        if (String.isBlank(info.primaryContactEmail)) { return; }
        
        EmailRequest req = new EmailRequest();
        req.toList = new List<String>{info.primaryContactEmail};
        req.templateName = Label.Payment_Term_Template_Confirmation;
        req.recordId = recordId;
        req.info = info;
        
        // FIX: Confirmation link should still show Client view
        req.urlUserType = 'Client';
        
        sendEmailGeneric(req);
    }

    private static void notifySupervisor(ParentInfo info, Id recordId) {
        if (String.isBlank(info.supervisorEmail)) { return; }
        
        EmailRequest req = new EmailRequest();
        req.toList = new List<String>{info.supervisorEmail};
        req.ccList = safeSplit(Label.Arelia_Living_Enrollment_Members);
        req.templateName = Label.Payment_Term_Template_Notify;
        req.recordId = recordId;
        req.info = info;
        
        // FIX: Supervisors view as Managers
        req.urlUserType = 'Manager';
        
        sendEmailGeneric(req);
    }

    private static void sendEmailGeneric(EmailRequest req) {
        if (req.toList == null || req.toList.isEmpty() || String.isBlank(req.templateName)) { return; }

        try {
            EmailTemplate et = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :req.templateName LIMIT 1];
            OrgWideEmailAddress owea = fetchOWD();

            // FIX: Use explicit urlUserType instead of guessing from template name
            String urlType = String.isNotBlank(req.urlUserType) ? req.urlUserType : 'Manager';
            String url = getBaseUrl() + '?id=' + req.recordId + '&type=' + urlType;
            
            Map<String, String> replacements = buildReplacements(req.info, url);

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            if (owea != null) { mail.setOrgWideEmailAddressId(owea.Id); }
            mail.setToAddresses(req.toList);
            if (req.ccList != null && !req.ccList.isEmpty()) { mail.setCcAddresses(req.ccList); }
            mail.setSubject(doReplace(et.Subject, replacements));
            mail.setHtmlBody(doReplace(et.HtmlValue, replacements));
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{mail});

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Email Failed: ' + e.getMessage());
        }
    }

    private static OrgWideEmailAddress fetchOWD() {
        if (String.isNotBlank(Label.Arelia_OWD)) {
            try { return [SELECT Id, Address FROM OrgWideEmailAddress WHERE Address = :Label.Arelia_OWD LIMIT 1]; } 
            catch (Exception e) { return null; }
        }
        return null;
    }

    private static Map<String, String> buildReplacements(ParentInfo info, String url) {
        Map<String, String> m = new Map<String, String>();
        m.put('{{OPPORTUNITY_NAME}}', safe(info.name));
        m.put('{{CLIENT_NAME}}', (info.primaryContactName != null) ? safe(info.primaryContactName) : 'Valued Client');
        m.put('{{CLIENT_PHONE}}', (info.primaryContactPhone != null) ? safe(info.primaryContactPhone) : 'N/A');
        m.put('{{CLIENT_EMAIL}}', (info.primaryContactEmail != null) ? safe(info.primaryContactEmail) : 'N/A');
        m.put('{{SUPERVISOR_NAME}}', (info.supervisorName != null) ? safe(info.supervisorName) : 'N/A');
        m.put('{{OWNER_NAME}}', (info.supervisorName != null) ? safe(info.supervisorName) : 'N/A');
        m.put('{{CURRENT_STATUS}}', safe(info.status));
        m.put('{{MANAGER_REMARKS}}', safe(info.managerRemarks));
        m.put('{{CLIENT_REMARKS}}', safe(info.clientRemarks));
        m.put('{{APPROVAL_LINK}}', (url != null) ? url : '#');
        return m;
    }

    private static String safe(String val) { return (val != null) ? val : ''; }

    private static String doReplace(String content, Map<String, String> replacements) {
        if (content == null) { return ''; }
        String res = content;
        for (String key : replacements.keySet()) { res = res.replace(key, replacements.get(key)); }
        return res;
    }

    public static List<String> safeSplit(String val) {
        return String.isNotBlank(val) ? val.split(',') : new List<String>();
    }
    
    public static String getBaseUrl() {
        return (Label.Arelia_Site_Label != null ? Label.Arelia_Site_Label : '') + (Label.Payment_Term_Page_Name != null ? Label.Payment_Term_Page_Name : '');
    }
}