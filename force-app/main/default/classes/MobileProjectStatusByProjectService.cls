@RestResource(urlMapping='/mobileProjectStatusByProject')
global without sharing class MobileProjectStatusByProjectService {

    @HttpPost
    global static MobileProjectStatusService.ResponseDTO getProject() {

        String raw = RestContext.request.requestBody.toString();
        Map<String, Object> input =
            (Map<String, Object>) JSON.deserializeUntyped(raw);

        String projectId = (String) input.get('projectId');

        if (String.isBlank(projectId)) {
            throw new AuraHandledException('ProjectId is required');
        }

        MobileProjectStatusService.ResponseDTO resp =
            new MobileProjectStatusService.ResponseDTO();

        resp.projects = new List<MobileProjectStatusService.ProjectDTO>();

        Project__c p = [
            SELECT Id, Name, Status__c,
                   Supervisor_Estimated_Budget__c,
                   Start_Date__c, End_Date__c,
                   Project_Completion_Status__c
            FROM Project__c
            WHERE Id = :projectId
            LIMIT 1
        ];

        MobileProjectStatusService.ProjectDTO dto =
            new MobileProjectStatusService.ProjectDTO();

        dto.projectId = p.Id;
        dto.projectName = p.Name;
        dto.projectStatus = p.Status__c;
        dto.budget = p.Supervisor_Estimated_Budget__c;
        dto.startDate = p.Start_Date__c;
        dto.endDate = p.End_Date__c;
        dto.completionPercentage = p.Project_Completion_Status__c;
        dto.vendors = new List<MobileProjectStatusService.VendorDTO>();

        // ✅ ADD THIS BLOCK (CRITICAL)
        List<Vendor_Assignment__c> vas = [
            SELECT Vendor__r.Name,
                   Vendor_Category__c,
                   Completion__c,
                   Vendor_Work_Start_Date__c,
                   Vendor_Work_End_Date__c,
                   Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Project__c = :p.Id
        ];

        for (Vendor_Assignment__c va : vas) {
            MobileProjectStatusService.VendorDTO v =
                new MobileProjectStatusService.VendorDTO();

            v.vendorName = va.Vendor__r != null ? va.Vendor__r.Name : null;
            v.vendorCategory = String.valueOf(va.Vendor_Category__c);
            v.completionPercentage = va.Completion__c;
            v.startDate = va.Vendor_Work_Start_Date__c;
            v.endDate = va.Vendor_Work_End_Date__c;
            v.remainingTasks = va.Vendor_Tasks_Remaining_Percentage__c;

            dto.vendors.add(v);
        }

        resp.projects.add(dto);
        resp.success = true;
        resp.message = 'Success';

        return resp;
    }
}