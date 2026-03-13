/**
 * @File Name         : InteriorMasterService.cls
 * @Description       : Returns all master data (types, categories, rooms, designs WITH room + file)
 *
 * PMD Notes:
 * - Read-only service for LWC.
 * - "without sharing" intentional for Experience/guest access.
 * - No SOQL in loops.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class InteriorMasterService {

    private static final String VERSION_DOWNLOAD_PATH = '/sfc/servlet.shepherd/version/download/';

    public class MasterDataDTO {
        @AuraEnabled public List<ProjectTypeDTO> projectTypes;
        @AuraEnabled public List<CategoryDTO>   categories;
        @AuraEnabled public List<RoomDTO>       rooms;
        @AuraEnabled public List<DesignDTO>     designs;
        @AuraEnabled public List<String>        designLevels;
    }

    public class ProjectTypeDTO { @AuraEnabled public Id id; @AuraEnabled public String name; }
    public class CategoryDTO { @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public Id projectTypeId; }
    public class RoomDTO { @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public Id categoryId; }

    public class DesignDTO {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public Id      categoryId;
        @AuraEnabled public Id      roomId;

        // your existing
        @AuraEnabled public String  designLevel;
        @AuraEnabled public Decimal basePrice;
        @AuraEnabled public String  description;
        @AuraEnabled public String  imageUrl;

        // ✅ NEW (your fields)
        @AuraEnabled public Decimal templateSizeSqft;  // Interior_Design__c.Size_sqft__c
        @AuraEnabled public Decimal ratePerSqft;       // Interior_Design__c.Rate_per_sqft__c
        @AuraEnabled public Decimal finalDesignPrice;  // Interior_Design__c.Final_Design_Price__c
    }

    @AuraEnabled(cacheable=true)
    public static MasterDataDTO getMasterData() {
        MasterDataDTO dto = new MasterDataDTO();

        dto.projectTypes = new List<ProjectTypeDTO>();
        for (Interior_Project_Type__c t : [SELECT Id, Name FROM Interior_Project_Type__c
            WHERE Active__c = true ORDER BY Name])
        {
            ProjectTypeDTO pt = new ProjectTypeDTO();
            pt.id = t.Id; pt.name = t.Name;
            dto.projectTypes.add(pt);
        }

        dto.categories = new List<CategoryDTO>();
        for (Interior_Category__c c : [SELECT Id, Name, Interior_Project_Type__c
                    FROM Interior_Category__c WHERE Active__c = true ORDER BY Name])
        {
            CategoryDTO cd = new CategoryDTO();
            cd.id = c.Id; cd.name = c.Name; cd.projectTypeId = c.Interior_Project_Type__c;
            dto.categories.add(cd);
        }

        dto.rooms = new List<RoomDTO>();
        for (Interior_Room__c r : [SELECT Id, Name, Interior_Category__c
                    FROM Interior_Room__c WHERE Active__c = true ORDER BY Name])
        {
            RoomDTO rd = new RoomDTO();
            rd.id = r.Id; rd.name = r.Name; rd.categoryId = r.Interior_Category__c;
            dto.rooms.add(rd);
        }

        List<Interior_Design__c> designRecs = [SELECT Id, Name, Interior_Category__c, Interior_Room__c,
                    Design_Level__c, Description__c, Size_sqft__c, Rate_per_sqft__c, Final_Design_Price__c
                    FROM Interior_Design__c WHERE Active__c = true ORDER BY Name];

        Set<Id> designIds = new Set<Id>();
        for (Interior_Design__c d : designRecs) designIds.add(d.Id);

        Map<Id, ContentDocumentLink> fileByDesign = new Map<Id, ContentDocumentLink>();
        if (!designIds.isEmpty()) {
            for (ContentDocumentLink cdl : [SELECT Id, LinkedEntityId, ContentDocument.LatestPublishedVersionId
                FROM ContentDocumentLink WHERE LinkedEntityId IN :designIds])
            {
                if (!fileByDesign.containsKey(cdl.LinkedEntityId)) fileByDesign.put(cdl.LinkedEntityId, cdl);
            }
        }

        dto.designs = new List<DesignDTO>();
        Set<String> levelsFromRecords = new Set<String>();

        for (Interior_Design__c d : designRecs) {
            DesignDTO dd = new DesignDTO();
            dd.id = d.Id;
            dd.name = d.Name;
            dd.categoryId = d.Interior_Category__c;
            dd.roomId = d.Interior_Room__c;

            dd.designLevel = d.Design_Level__c;
            dd.description = d.Description__c;

            // ✅ NEW
            dd.templateSizeSqft = d.Size_sqft__c;
            dd.ratePerSqft = d.Rate_per_sqft__c;
            dd.finalDesignPrice = d.Final_Design_Price__c;

            if (dd.designLevel != null) {levelsFromRecords.add(dd.designLevel);}

            if (fileByDesign.containsKey(d.Id)) {
                Id verId = fileByDesign.get(d.Id).ContentDocument.LatestPublishedVersionId;
                dd.imageUrl = buildFileDownloadUrl(verId);
            }
            dto.designs.add(dd);
        }

        List<String> finalLevels = new List<String>();
        Schema.DescribeFieldResult dfr = Interior_Design__c.Design_Level__c.getDescribe();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues())
        {
            finalLevels.add(pe.getLabel());
        }
        for (String recLvl : levelsFromRecords)
        {
            if (!finalLevels.contains(recLvl))
            {
                finalLevels.add(recLvl);
            }
        }

        dto.designLevels = finalLevels;
        return dto;
    }

    private static String buildFileDownloadUrl(Id versionId) {
        return versionId == null ? null : (VERSION_DOWNLOAD_PATH + String.valueOf(versionId));
    }
}