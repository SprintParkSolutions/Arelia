@SuppressWarnings('PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class ProjectMilestoneController {

    public class MilestoneResponse {
        @AuraEnabled public Decimal completionPercentage;
        @AuraEnabled public List<MilestoneDTO> milestones;
    }

    public class MilestoneDTO {
        @AuraEnabled public Id paymentTermId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public Decimal cumulativePercentage;
        @AuraEnabled public Boolean completed;
        @AuraEnabled public Boolean paymentReceived; // 🔹 NEW
    }

    @AuraEnabled(cacheable=true)
    public static MilestoneResponse getMilestones(Id projectId) {

        MilestoneResponse response = new MilestoneResponse();
        response.milestones = new List<MilestoneDTO>();
        response.completionPercentage = 0;

        if (projectId == null) {
            return response;
        }

        // 1️⃣ Project completion %
        Project__c project = [
            SELECT Project_Completion_Status__c
            FROM Project__c
            WHERE Id = :projectId
            LIMIT 1
        ];

        response.completionPercentage =
            project.Project_Completion_Status__c != null
                ? project.Project_Completion_Status__c.setScale(2)
                : 0;

        // 2️⃣ Payment Terms (WITH Payment_Received__c)
        List<Payment_Term__c> paymentTerms = [
            SELECT Id,
                   Name,
                   Percentage__c,
                   Payment_Received__c
            FROM Payment_Term__c
            WHERE Project__c = :projectId
            ORDER BY CreatedDate
        ];

        Decimal cumulative = 0;

        for (Payment_Term__c term : paymentTerms) {
            cumulative += term.Percentage__c;

            MilestoneDTO dto = new MilestoneDTO();
            dto.paymentTermId = term.Id;
            dto.name = term.Name;
            dto.percentage = term.Percentage__c;
            dto.cumulativePercentage = cumulative;
            dto.completed = response.completionPercentage >= cumulative;
            dto.paymentReceived = term.Payment_Received__c; // 🔹 NEW

            response.milestones.add(dto);
        }

        return response;
    }
}