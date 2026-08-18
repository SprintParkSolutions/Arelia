/**
 * @description Lets a project supervisor view their assigned projects and send a weekly
 * progress update email to the client, with public (no-login) links to any attached files.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class WeeklyProjectUpdateController {

    /**
     * @description Returns the projects supervised by the running user, most recently started first.
     * @return Project__c records where Supervisor_User__c is the current user.
     */
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

    /**
     * @description Sends the weekly progress update email for a project to its client,
     * CC'ing the supervisor and the management distribution list.
     * @param projectId Project__c Id the update is for.
     * @param weeklySummary Free-text summary of the week's progress.
     * @param fileIds ContentDocument Ids to share as public file links in the email.
     */
    @AuraEnabled
    public static void sendWeeklyEmail(Id projectId, String weeklySummary, List<Id> fileIds) {
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

        Integer weekNo = 1;
        if (proj.Start_Date__c != null) {
            weekNo = (Date.today().daysBetween(proj.Start_Date__c) / 7) + 1;
        }

        EmailTemplate tpl = [
            SELECT Id, HtmlValue, Subject
            FROM EmailTemplate
            WHERE DeveloperName = 'Weekly_Project_Update_Template'
            LIMIT 1
        ];

        String fileLinksHtml = buildFileLinksHtml(fileIds);

        String body = tpl.HtmlValue
            .replace('{{{ClientName}}}', proj.Client__r != null ? proj.Client__r.Name : '')
            .replace('{{{ProjectName}}}', proj.Name != null ? proj.Name : '')
            .replace('{{{ProjectStatus}}}', proj.Project_Status__c != null ? proj.Project_Status__c : '')
            .replace('{{{ProjectStartDate}}}', proj.Start_Date__c != null ? String.valueOf(proj.Start_Date__c) : '')
            .replace('{{{WeekNumber}}}', String.valueOf(weekNo))
            .replace('{{{WeeklySummary}}}', weeklySummary != null ? weeklySummary : '')
            .replace('{{{SupervisorName}}}', proj.Supervisor_User__r != null ? proj.Supervisor_User__r.Name : UserInfo.getName())
            .replace('{{{FileLinks}}}', String.isNotBlank(fileLinksHtml) ? fileLinksHtml : 'No files uploaded');

        String subject = tpl.Subject
            .replace('{{{ProjectName}}}', proj.Name != null ? proj.Name : '')
            .replace('{{{WeekNumber}}}', String.valueOf(weekNo));

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ proj.Client_Email__c });

        List<String> ccAddresses = buildCcAddresses(proj);
        if (!ccAddresses.isEmpty()) {
            mail.setCcAddresses(ccAddresses);
        }

        mail.setSubject(subject);
        mail.setHtmlBody(body);
        mail.setWhatId(proj.Id);
        mail.setSaveAsActivity(true);
        AreliaUtility.setOrgWideEmailAddress(mail, System.Label.Arelia_OWD);

        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
    }

    // Creates public (no-login) view links for each file so clients without a portal login can open them.
    private static String buildFileLinksHtml(List<Id> fileIds) {
        if (fileIds == null || fileIds.isEmpty()) {
            return '';
        }

        Map<Id, ContentVersion> versionByVersionId = new Map<Id, ContentVersion>();
        for (ContentVersion cv : [
            SELECT Id, Title, FileType
            FROM ContentVersion
            WHERE ContentDocumentId IN :fileIds
            AND IsLatest = true
        ]) {
            versionByVersionId.put(cv.Id, cv);
        }

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

        String fileLinksHtml = '';
        for (ContentDistribution dist : [
            SELECT DistributionPublicUrl, ContentVersionId
            FROM ContentDistribution
            WHERE ContentVersionId IN :versionByVersionId.keySet()
        ]) {
            fileLinksHtml += buildFileLinkHtml(dist, versionByVersionId.get(dist.ContentVersionId));
        }
        return fileLinksHtml;
    }

    private static String buildFileLinkHtml(ContentDistribution dist, ContentVersion cv) {
        String fileType = cv.FileType != null ? cv.FileType.toUpperCase() : '';

        if (fileType == 'JPG' || fileType == 'PNG' || fileType == 'JPEG') {
            return '<div style="margin-bottom:12px;">' +
                '🖼 <a href="' + dist.DistributionPublicUrl + '" target="_blank">View Image: ' + cv.Title + '</a>' +
                '</div>';
        }
        if (fileType == 'MP4' || fileType == 'MOV') {
            return '<div style="margin-bottom:12px;">' +
                '<a href="' + dist.DistributionPublicUrl + '?download=1" target="_blank">▶️ <strong>Download & Play Video:</strong> ' + cv.Title + '</a>' +
                '</div>';
        }
        return '<div style="margin-bottom:12px;">' +
            '<a href="' + dist.DistributionPublicUrl + '" target="_blank">' + cv.Title + '</a>' +
            '</div>';
    }

    // CC's the supervisor plus the management distribution list, de-duplicated.
    private static List<String> buildCcAddresses(Project__c proj) {
        List<String> ccAddresses = new List<String>();

        if (proj.Supervisor_User__r != null && String.isNotBlank(proj.Supervisor_User__r.Email)) {
            ccAddresses.add(proj.Supervisor_User__r.Email.trim());
        }

        String labelEmails = Label.Arelia_Living_Management_Members;
        if (String.isNotBlank(labelEmails)) {
            for (String email : labelEmails.split('[,;]')) {
                if (String.isNotBlank(email)) {
                    ccAddresses.add(email.trim());
                }
            }
        }

        return new List<String>(new Set<String>(ccAddresses));
    }
}