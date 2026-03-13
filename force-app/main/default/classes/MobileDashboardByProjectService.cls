@RestResource(urlMapping='/mobile/dashboard-by-project')
global without sharing class MobileDashboardByProjectService {

    @HttpPost
    global static DashboardResponse getDashboard() {

        String raw = RestContext.request.requestBody.toString();
        Map<String, Object> input =
            (Map<String, Object>) JSON.deserializeUntyped(raw);

        String projectId = (String) input.get('projectId');

        if (String.isBlank(projectId)) {
            throw new AuraHandledException('ProjectId is required');
        }

        Project__c p = [
            SELECT Name,
                   Supervisor_Estimated_Budget__c,
                   Project_Completion_Status__c
            FROM Project__c
            WHERE Id = :projectId
            LIMIT 1
        ];

        DashboardResponse res = new DashboardResponse();
        res.projectName = p.Name;
        res.budget = p.Supervisor_Estimated_Budget__c;
        res.progress = p.Project_Completion_Status__c;

        return res;
    }

    global class DashboardResponse {
        public String projectName;
        public Decimal budget;
        public Decimal progress;
    }
}