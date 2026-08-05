@RestResource(urlMapping='/mobile/getProjectByContact')
global without sharing class MobileGetProjectByContactService {

    global class ProjectDTO {
        public String projectId;
        public String projectName;
    }

    @HttpPost
    global static ProjectDTO getProjectByContact() {
        String rawBody = RestContext.request.requestBody == null
            ? null
            : RestContext.request.requestBody.toString();

        Map<String, Object> input =
            String.isBlank(rawBody)
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(rawBody);

        String contactId = (String) input.get('contactId');
        String email = (String) input.get('email');

        if (String.isBlank(contactId) && String.isBlank(email)) {
            return null;
        }

        List<Project__c> projects = [
            SELECT Id, Name
            FROM Project__c
            WHERE Client__c = :contactId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (projects.isEmpty() && !String.isBlank(email)) {
            projects = [
                SELECT Id, Name
                FROM Project__c
                WHERE Client__r.Email = :email
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        }

        if (projects.isEmpty()) {
            return null;
        }

        ProjectDTO dto = new ProjectDTO();
        dto.projectId = projects[0].Id;
        dto.projectName = projects[0].Name;
        return dto;
    }
}