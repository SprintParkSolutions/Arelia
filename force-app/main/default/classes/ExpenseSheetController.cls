/**
 * Controller for Expense Sheet Entry and Approval.
 * Uses "without sharing" to allow Guest Users/Managers to approve records via Experience Site.
 * Developed for the Arelia Living project.
 */
@SuppressWarnings('PMD.ApexCRUDViolation') 
public without sharing class ExpenseSheetController {

    // --- WRAPPERS ---
    public class SheetData {
        @AuraEnabled public String sheetId;
        @AuraEnabled public String projectId;
        @AuraEnabled public Decimal grandTotal;
        @AuraEnabled public String status; 
        @AuraEnabled public List<LineItemData> items;
        @AuraEnabled public List<FileData> billFiles;     
        @AuraEnabled public List<FileData> existingFiles; 
    }

    public class FileData {
        @AuraEnabled public String name;
        @AuraEnabled public String base64;
        @AuraEnabled public String docId;
    }

    public class LineItemData {
        @AuraEnabled public String type; 
        @AuraEnabled public String name;
        @AuraEnabled public String brand;
        @AuraEnabled public Decimal qty;
        @AuraEnabled public Decimal rate;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String description;
    }

    // --- MAIN SAVE METHOD ---
    @AuraEnabled
    public static String saveExpenseSheet(String jsonData) {
        try {
            SheetData data = (SheetData) JSON.deserialize(jsonData, SheetData.class);
            Project_Expense_Sheet__c sheet = new Project_Expense_Sheet__c();
            
            if (String.isNotBlank(data.sheetId)) {
                sheet.Id = data.sheetId;
                delete [SELECT Id FROM Expense_Line_Item__c WHERE Project_Expense_Sheet__c = :data.sheetId];
            } else {
                sheet.Project__c = data.projectId;
            }

            sheet.Sheet_Date__c = Date.today();
            sheet.Status__c = data.status; 
            upsert sheet; 

            List<Expense_Line_Item__c> lines = new List<Expense_Line_Item__c>();
            for (LineItemData item : data.items) {
                lines.add(new Expense_Line_Item__c(
                    Project_Expense_Sheet__c = sheet.Id,
                    Type__c = item.type,
                    Item_Name__c = item.name,
                    Brand__c = item.brand,
                    Quantity__c = item.qty,
                    Rate__c = item.rate,
                    Amount__c = item.amount,
                    Description__c = item.description
                ));
            }
            insert lines;

            if (data.billFiles != null && !data.billFiles.isEmpty()) {
                List<ContentVersion> cvList = new List<ContentVersion>();
                for (FileData file : data.billFiles) {
                    ContentVersion cv = new ContentVersion();
                    cv.Title = file.name;
                    cv.PathOnClient = file.name;
                    cv.VersionData = EncodingUtil.base64Decode(file.base64);
                    cv.FirstPublishLocationId = sheet.Id;
                    cvList.add(cv);
                }
                insert cvList;
            }

            if (data.status == 'Submitted') {
                generatePDFAndSendEmail(sheet.Id);
            }

            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // --- ASYNC PDF GENERATION ---
    @Future(callout=true)
    public static void generatePDFAndSendEmail(Id sheetId) {
        List<ContentDocumentLink> oldPdfs = [
            SELECT ContentDocumentId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :sheetId 
            AND ContentDocument.Title = 'Expense_Report.pdf'
        ];
        
        if (!oldPdfs.isEmpty()) {
            List<ContentDocument> docsToDelete = new List<ContentDocument>();
            for (ContentDocumentLink link : oldPdfs) {
                docsToDelete.add(new ContentDocument(Id = link.ContentDocumentId));
            }
            delete docsToDelete;
        }

        PageReference pdf = Page.ExpenseSheetPDF;
        pdf.getParameters().put('id', sheetId);
        Blob pdfBlob = Test.isRunningTest() ? Blob.valueOf('Test') : pdf.getContentAsPDF();
        createFile(sheetId, 'Expense_Report.pdf', pdfBlob);
        
        sendManagerApprovalEmail(sheetId);
    }

    // --- EMAIL TO MANAGERS ---
    private static void sendManagerApprovalEmail(Id sheetId) {
        Project_Expense_Sheet__c sheet = [SELECT Id, Name, Grand_Total__c, Project__r.Name, CreatedBy.Name FROM Project_Expense_Sheet__c WHERE Id = :sheetId];
        String managerEmails = System.Label.Arelia_Living_Enrollment_Members;
        String fullUrl = System.Label.Arelia_Site_Label + System.Label.Arelia_Expense_Approval_Page + '?c__recordId=' + sheet.Id;

        EmailTemplate tpl = [SELECT Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :System.Label.Arelia_Expense_Template LIMIT 1];
        String htmlBody = tpl.HtmlValue
            .replace('{ProjectName}', sheet.Project__r.Name)
            .replace('{SubmitterName}', sheet.CreatedBy.Name)
            .replace('{GrandTotal}', '₹ ' + sheet.Grand_Total__c)
            .replace('{ApprovalLink}', fullUrl);
        String subject = tpl.Subject.replace('{ProjectName}', sheet.Project__r.Name);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(managerEmails.split(','));
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        mail.setSaveAsActivity(false); 

        attachAllFilesToEmail(mail, sheetId);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    // --- STATUS UPDATE & SUPERVISOR NOTIFICATION ---
    @AuraEnabled
    public static String updateSheetStatus(String sheetId, String status) {
        Project_Expense_Sheet__c sheet = [SELECT Id, Project__c FROM Project_Expense_Sheet__c WHERE Id = :sheetId LIMIT 1];
        sheet.Status__c = status;
        update sheet;

        recalculateProjectTotal(sheet.Project__c);

        if (status == 'Approved') {
            sendApprovalNotification(sheet.Id);
        }

        return 'Success';
    }

    /**
     * Sends notification email to Supervisor with Full Name and ALL Attachments
     */
    private static void sendApprovalNotification(Id sheetId) {
        Project_Expense_Sheet__c sheet = [
            SELECT Id, Name, Grand_Total__c, Project__r.Name, Project__r.Client__r.Name, 
                   CreatedBy.Email, CreatedBy.Name,
                   Project__r.Supervisor_User__r.Email, 
                   Project__r.Supervisor_User__r.FirstName, // <--- Explicitly use FirstName
                   Project__r.Supervisor_User__r.LastName   // <--- Explicitly use LastName
            FROM Project_Expense_Sheet__c 
            WHERE Id = :sheetId
        ];

        // 1. Build Proper Full Name (Prevents Nickname usage)
        String supervisorFullName = '';
        if (String.isNotBlank(sheet.Project__r.Supervisor_User__r.FirstName)) {
            supervisorFullName += sheet.Project__r.Supervisor_User__r.FirstName + ' ';
        }
        if (String.isNotBlank(sheet.Project__r.Supervisor_User__r.LastName)) {
            supervisorFullName += sheet.Project__r.Supervisor_User__r.LastName;
        }
        if (String.isBlank(supervisorFullName.trim())) {
            supervisorFullName = 'Supervisor';
        }

        String templateName = System.Label.Arelia_Expense_Approved_Template;
        EmailTemplate tpl = [SELECT Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :templateName LIMIT 1];
        
        String owdEmail = System.Label.Arelia_OWD;
        OrgWideEmailAddress[] owea = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :owdEmail];

        if (tpl == null) {
            return;
        }

        String htmlBody = tpl.HtmlValue
            .replace('{SupervisorName}', supervisorFullName.trim())
            .replace('{SubmitterName}', sheet.CreatedBy.Name)
            .replace('{ProjectName}', sheet.Project__r.Name)
            .replace('{ClientName}', (sheet.Project__r.Client__r.Name != null ? sheet.Project__r.Client__r.Name : 'N/A'))
            .replace('{SheetName}', sheet.Name)
            .replace('{GrandTotal}', '₹ ' + sheet.Grand_Total__c);
        
        String subject = tpl.Subject.replace('{ProjectName}', sheet.Project__r.Name);

        List<String> recipients = new List<String>();
        if (String.isNotBlank(sheet.Project__r.Supervisor_User__r.Email)) {
            recipients.add(sheet.Project__r.Supervisor_User__r.Email);
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        if (owea.size() > 0) {
            mail.setOrgWideEmailAddressId(owea[0].Id);
        }

        mail.setToAddresses(recipients); 
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        mail.setSaveAsActivity(false); 

        // 2. ATTACH ALL FILES (PDF + Bills)
        attachAllFilesToEmail(mail, sheetId);
        
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    // --- HELPER: ATTACH ALL FILES ---
    private static void attachAllFilesToEmail(Messaging.SingleEmailMessage mail, Id sheetId) {
        Set<Id> versionIds = new Set<Id>();
        for (ContentDocumentLink cdl : [SELECT ContentDocument.LatestPublishedVersionId FROM ContentDocumentLink WHERE LinkedEntityId = :sheetId]) {
            versionIds.add(cdl.ContentDocument.LatestPublishedVersionId);
        }
        if (!versionIds.isEmpty()) {
            List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
            for (ContentVersion cv : [SELECT Title, FileExtension, VersionData FROM ContentVersion WHERE Id IN :versionIds]) {
                Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
                String ext = (cv.FileExtension != null) ? cv.FileExtension : 'pdf';
                String fileName = cv.Title;
                if (!fileName.contains('.')) {
                    fileName += '.' + ext;
                }
                att.setFileName(fileName);
                att.setBody(cv.VersionData);
                attachments.add(att);
            }
            mail.setFileAttachments(attachments);
        }
    }

    // --- ROLLUP LOGIC ---
    private static void recalculateProjectTotal(Id projectId) {
        if (projectId == null) {
            return;
        }
        AggregateResult[] results = [SELECT SUM(Grand_Total__c) totalAmount FROM Project_Expense_Sheet__c WHERE Project__c = :projectId AND Status__c = 'Approved'];
        Decimal total = 0;
        if (!results.isEmpty() && results[0].get('totalAmount') != null) {
            total = (Decimal)results[0].get('totalAmount');
        }
        Project__c proj = new Project__c(Id = projectId);
        proj.Total_Approved_Expenses__c = total; 
        update proj;
    }

    // --- OTHER HELPERS (DRAFT LOADING, ETC) ---
    @AuraEnabled(cacheable=true)
    public static Project_Expense_Sheet__c getSheetDetails(String sheetId) {
        return [SELECT Id, Name, Grand_Total__c, Sheet_Date__c, Status__c, Project__r.Name, Project__r.Client__r.Name FROM Project_Expense_Sheet__c WHERE Id = :sheetId];
    }
    
    @AuraEnabled
    public static SheetData getDraftDetails(String sheetId) {
        Project_Expense_Sheet__c sheet = [SELECT Id, Project__c, Grand_Total__c, Status__c FROM Project_Expense_Sheet__c WHERE Id = :sheetId];
        List<Expense_Line_Item__c> lines = [SELECT Type__c, Item_Name__c, Brand__c, Quantity__c, Rate__c, Amount__c, Description__c FROM Expense_Line_Item__c WHERE Project_Expense_Sheet__c = :sheetId];
        List<ContentDocumentLink> fileLinks = [SELECT ContentDocument.LatestPublishedVersion.Title, ContentDocument.LatestPublishedVersion.FileExtension, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :sheetId];

        SheetData data = new SheetData();
        data.sheetId = sheet.Id;
        data.projectId = sheet.Project__c;
        data.grandTotal = sheet.Grand_Total__c;
        data.status = sheet.Status__c;
        data.items = new List<LineItemData>();
        for (Expense_Line_Item__c line : lines) {
            LineItemData item = new LineItemData();
            item.type = line.Type__c;
            item.name = line.Item_Name__c;
            item.brand = line.Brand__c;
            item.qty = line.Quantity__c;
            item.rate = line.Rate__c;
            item.amount = line.Amount__c;
            item.description = line.Description__c;
            data.items.add(item);
        }
        data.existingFiles = new List<FileData>();
        for (ContentDocumentLink link : fileLinks) {
            if (!link.ContentDocument.LatestPublishedVersion.Title.startsWith('Expense_Report')) {
                FileData file = new FileData();
                file.name = link.ContentDocument.LatestPublishedVersion.Title + '.' + link.ContentDocument.LatestPublishedVersion.FileExtension;
                file.docId = link.ContentDocumentId;
                data.existingFiles.add(file);
            }
        }
        return data;
    }

    @AuraEnabled(cacheable=true)
    public static List<Project_Expense_Sheet__c> getProjectExpenses(String projectId) {
        return [SELECT Id, Name, Sheet_Date__c, Grand_Total__c, CreatedBy.Name, CreatedDate, Status__c FROM Project_Expense_Sheet__c WHERE Project__c = :projectId ORDER BY CreatedDate DESC];
    }

    private static Id createFile(Id parentId, String title, Blob body) {
        ContentVersion cv = new ContentVersion();
        cv.Title = title;
        cv.PathOnClient = title;
        cv.VersionData = body;
        cv.FirstPublishLocationId = parentId; 
        insert cv;
        return cv.Id;
    }
}