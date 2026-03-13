public with sharing class WeeklyProjectUpdateController {

    /* ===============================
       STEP 1: Get Supervisor Projects
    =============================== */
    @AuraEnabled(cacheable=true)
    public static List<Project__c> getSupervisorProjects() {
        return [
            SELECT Id,
                   Name,
                   Client__r.Name,
                   Client_Email__c,
                   Start_Date__c,
                   Status__c,
                   Project_Status__c,
                   Supervisor_User__c
            FROM Project__c
            WHERE Supervisor_User__c = :UserInfo.getUserId()
            ORDER BY Start_Date__c DESC
        ];
    }

    /* ===============================
       STEP 2: Send Weekly Update Email
       (PUBLIC FILE LINKS – NO LOGIN)
    =============================== */
    @AuraEnabled
    public static void sendWeeklyEmail(
        Id projectId,
        String weeklySummary,
        List<Id> fileIds
    ) {

        /* ===============================
           FETCH PROJECT
        =============================== */
        Project__c proj = [
            SELECT Id,
                   Name,
                   Client__r.Name,
                   Client_Email__c,
                   Start_Date__c,
                   Project_Status__c,
                   Supervisor_User__r.Name,
                   Supervisor_User__r.Email
            FROM Project__c
            WHERE Id = :projectId
            LIMIT 1
        ];

        if (String.isBlank(proj.Client_Email__c)) {
            throw new AuraHandledException('Client email is missing.');
        }

        /* ===============================
           WEEK CALCULATION
        =============================== */
        Integer weekNo = 1;
        if (proj.Start_Date__c != null) {
            weekNo = (Date.today().daysBetween(proj.Start_Date__c) / 7) + 1;
        }

        /* ===============================
           FETCH EMAIL TEMPLATE
        =============================== */
        EmailTemplate tpl = [
            SELECT Id, HtmlValue, Subject
            FROM EmailTemplate
            WHERE DeveloperName = 'Weekly_Project_Update_Template'
            LIMIT 1
        ];

        /* ===============================
   CREATE PUBLIC FILE LINKS (NO LOGIN)
=============================== */
String fileLinksHtml = '';

if (fileIds != null && !fileIds.isEmpty()) {

    Map<Id, ContentVersion> versionByVersionId = new Map<Id, ContentVersion>();

    // 1️⃣ Fetch latest versions
    for (ContentVersion cv : [
        SELECT Id, Title, FileType
        FROM ContentVersion
        WHERE ContentDocumentId IN :fileIds
        AND IsLatest = true
    ]) {
        versionByVersionId.put(cv.Id, cv);
    }

    // 2️⃣ Create Content Distributions
    List<ContentDistribution> distList = new List<ContentDistribution>();

    for (ContentVersion cv : versionByVersionId.values()) {
        ContentDistribution cd = new ContentDistribution();
        cd.ContentVersionId = cv.Id;
        cd.Name = cv.Title;
        cd.PreferencesAllowViewInBrowser = true;
        cd.PreferencesLinkLatestVersion = true;
        cd.PreferencesPasswordRequired = false;
        distList.add(cd);
    }

    insert distList;

    //  Build HTML (SAFE)
    for (ContentDistribution dist : [
        SELECT DistributionPublicUrl, ContentVersionId
        FROM ContentDistribution
        WHERE ContentVersionId IN :versionByVersionId.keySet()
    ]) {

        ContentVersion cv = versionByVersionId.get(dist.ContentVersionId);
        String fileType = cv.FileType != null ? cv.FileType.toUpperCase() : '';

        /// IMAGE → LINK (EMAIL SAFE)
if (fileType == 'JPG' || fileType == 'PNG' || fileType == 'JPEG') {
    fileLinksHtml +=
        '<div style="margin-bottom:12px;">' +
        '🖼 <a href="' + dist.DistributionPublicUrl + '" target="_blank">' +
        'View Image: ' + cv.Title +
        '</a>' +
        '</div>';
}
        //  VIDEO LINK (EMAIL-SAFE)
        else if (fileType == 'MP4' || fileType == 'MOV') {
    fileLinksHtml +=
        '<div style="margin-bottom:12px;">' +
        '<a href="' + dist.DistributionPublicUrl + '?download=1" target="_blank">' +
        '▶️ <strong>Download & Play Video:</strong> ' + cv.Title +
        '</a>' +
        '</div>';
}
        // 📄 OTHER FILES // 
        else {
            fileLinksHtml +=
                '<div style="margin-bottom:12px;">' +
                '<a href="' + dist.DistributionPublicUrl + '" target="_blank">' +
                cv.Title +
                '</a>' +
                '</div>';
        }
    }
}


        /* ===============================
           MERGE EMAIL BODY
        =============================== */
        String body = tpl.HtmlValue
            .replace('{{{ClientName}}}', proj.Client__r != null ? proj.Client__r.Name : '')
            .replace('{{{ProjectName}}}', proj.Name != null ? proj.Name : '')
            .replace('{{{ProjectStatus}}}', proj.Project_Status__c != null ? proj.Project_Status__c : '')
            .replace('{{{ProjectStartDate}}}', proj.Start_Date__c != null ? String.valueOf(proj.Start_Date__c) : '')
            .replace('{{{WeekNumber}}}', String.valueOf(weekNo))
            .replace('{{{WeeklySummary}}}', weeklySummary != null ? weeklySummary : '')
            .replace('{{{SupervisorName}}}',
                proj.Supervisor_User__r != null
                    ? proj.Supervisor_User__r.Name
                    : UserInfo.getName()
            )
            .replace(
    '{{{FileLinks}}}',
    fileLinksHtml != ''
        ? fileLinksHtml
        : 'No files uploaded'
);

        /* ===============================
           MERGE SUBJECT
        =============================== */
        String subject = tpl.Subject
            .replace('{{{ProjectName}}}', proj.Name != null ? proj.Name : '')
            .replace('{{{WeekNumber}}}', String.valueOf(weekNo));

        /* ===============================
           SEND EMAIL
        =============================== */
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
mail.setToAddresses(new List<String>{ proj.Client_Email__c });

// ===============================
// CC ADDRESSES (Supervisor + Label)
// ===============================
List<String> ccAddresses = new List<String>();

//  Supervisor Email
if (proj.Supervisor_User__r != null &&
    String.isNotBlank(proj.Supervisor_User__r.Email)) {
    ccAddresses.add(proj.Supervisor_User__r.Email.trim());
}

//  Custom Label Emails
String labelEmails = Label.Arelia_Living_Enrollment_Members;
if (String.isNotBlank(labelEmails)) {
    List<String> extras = labelEmails.split('[,;]');
    for (String email : extras) {
        if (String.isNotBlank(email)) {
            ccAddresses.add(email.trim());
        }
    }
}

//  REMOVE DUPLICATES
ccAddresses = new List<String>(new Set<String>(ccAddresses));

//  Set CC if present
if (!ccAddresses.isEmpty()) {
    mail.setCcAddresses(ccAddresses);
}
        mail.setSubject(subject);
        mail.setHtmlBody(body);
        mail.setWhatId(proj.Id);
        mail.setSaveAsActivity(true);

        // Org-Wide Email
        Id owdId = getOWD();
        if (owdId != null) {
            mail.setOrgWideEmailAddressId(owdId);
        }

        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
    }

    /* ===============================
       ORG-WIDE EMAIL
    =============================== */
    public static Id getOWD() {
        List<OrgWideEmailAddress> ow = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE IsAllowAllProfiles = true
            LIMIT 1
        ];
        return ow.isEmpty() ? null : ow[0].Id;
    }
}