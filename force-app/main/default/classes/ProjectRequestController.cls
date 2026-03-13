/**
 * @FileName    : ProjectRequestController.cls
 * @description : Provides helper methods for the Project Request wizard
 *                (quotation type picklist).
 */


    public without sharing class ProjectRequestController {
 
    // DTO to return both Label and Value
    public class PicklistOptionDTO {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
 
        public PicklistOptionDTO(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
 
    /**
     * @description Returns the available picklist values (Label + Value) for
     *              Lead.Project_Request_Quotation_Type__c.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOptionDTO> getProjectQuotationTypeValues() {
        List<PicklistOptionDTO> options = new List<PicklistOptionDTO>();
 
        Schema.DescribeFieldResult fieldResult =
            Lead.Project_Request_Quotation_Type__c.getDescribe();
 
        for (Schema.PicklistEntry pe : fieldResult.getPicklistValues()) {
            if (pe != null && pe.isActive()) {
                options.add(new PicklistOptionDTO(pe.getLabel(), pe.getValue()));
            }
        }
        return options;
    }
}