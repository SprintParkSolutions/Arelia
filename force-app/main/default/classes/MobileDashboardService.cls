@RestResource(urlMapping='/mobile/dashboard')
global without sharing class MobileDashboardService {

    @HttpGet
    global static DashboardResponse getDashboard() {
        String contactId = RestContext.request.params.get('contactId');
        String projectId = RestContext.request.params.get('projectId');

        if (String.isBlank(contactId)) {
            throw new AuraHandledException('ContactId is required');
        }

        Contact c = [
            SELECT Name, Email
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];

        Project__c p;

        if (!String.isBlank(projectId)) {
            List<Project__c> projects = [
                SELECT Id, Name, Supervisor_Estimated_Budget__c,
                    Project_Completion_Status__c, Start_Date__c, Estimated_End_Date__c
                FROM Project__c
                WHERE Id = :projectId
                  AND Client__c = :contactId
                LIMIT 1
            ];
            p = projects.isEmpty() ? null : projects[0];
        } else {
            List<Project__c> projects = [
                SELECT Id, Name, Supervisor_Estimated_Budget__c,
                    Project_Completion_Status__c, Start_Date__c, Estimated_End_Date__c
                FROM Project__c
                WHERE Client__c = :contactId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            p = projects.isEmpty() ? null : projects[0];
        }

        DashboardResponse res = new DashboardResponse();
        res.userName = c.Name;
        res.userEmail = c.Email;

        if (p != null) {
            res.projectId = p.Id;
            res.projectName = p.Name;
            res.budget = p.Supervisor_Estimated_Budget__c;
            res.progress = p.Project_Completion_Status__c;
            res.startDate = p.Start_Date__c;
            res.endDate = p.Estimated_End_Date__c;
        } else {
            res.projectName = 'No Active Project';
            res.budget = 0;
            res.progress = 0;
        }

        return res;
    }

    global class DashboardResponse {
        public String userName;
        public String userEmail;
        public String projectId;
        public String projectName;
        public Decimal budget;
        public Decimal progress;
        public Date startDate;
        public Date endDate;
    }
}