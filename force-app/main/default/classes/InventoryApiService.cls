public without sharing class InventoryApiService {

    /* ===============================
       STEP 1 + STEP 2
       Fetch Room Types & Categories
       based on Opportunity context
    =============================== */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getCatalogConfig(Id opportunityId) {

        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required');
        }

        // 1️⃣ Get Opportunity context
        Opportunity opp = [
            SELECT Type_of_Project__c,Interior_Project_Type_Value_Name__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        /*if (String.isBlank(opp.Type_of_Project__c)) {
            throw new AuraHandledException('Type of Project is not set on Opportunity');
        }*/

        String projectTypeValue = String.isNotBlank(opp.Type_of_Project__c) ? opp.Type_of_Project__c : opp.Interior_Project_Type_Value_Name__c;

        // 2️⃣ Get product-based configuration
        List<Interior_Product__c> products = [
            SELECT Room_Type__c, Product_Category__c
            FROM Interior_Product__c
            WHERE Type_of_Project__c = :projectTypeValue ORDER BY Room_Type__c ASC
        ];
        System.debug('products List::'+products);

        // 3️⃣ Build dynamic dependency structure
        Set<String> roomSet = new Set<String>();
        Map<String, Set<String>> categoryMap = new Map<String, Set<String>>();

        for (Interior_Product__c p : products) {
            if (String.isBlank(p.Room_Type__c) || String.isBlank(p.Product_Category__c)) {
                continue;
            }

            roomSet.add(p.Room_Type__c);

            if (!categoryMap.containsKey(p.Room_Type__c)) {
                categoryMap.put(p.Room_Type__c, new Set<String>());
            }
            categoryMap.get(p.Room_Type__c).add(p.Product_Category__c);
        }

        // 4️⃣ Convert Sets → Lists (LWC-friendly)
        Map<String, Object> result = new Map<String, Object>();
        result.put('rooms', new List<String>(roomSet));

        Map<String, List<String>> finalCategoryMap = new Map<String, List<String>>();
        for (String room : categoryMap.keySet()) {
            finalCategoryMap.put(room, new List<String>(categoryMap.get(room)));
        }

        result.put('categoriesByRoom', finalCategoryMap);
        return result;
    }
@AuraEnabled(cacheable=true)
public static Opportunity getOpportunitySummary(Id opportunityId) {
    return [
        SELECT
            Lead_Name__c,
            Email__c,            
            Type_of_Project__c,
            Project_Request_Quotation_Type__c,
            Interior_Project_Type__r.Name
        FROM Opportunity
        WHERE Id = :opportunityId
        LIMIT 1
    ];
}


    /* ===============================
       STEP 3
       Load Products (UNCHANGED)
    =============================== */
    @AuraEnabled(cacheable=true)
public static List<Map<String,Object>> getProducts(String roomType, String category) {

    if (String.isBlank(roomType) || String.isBlank(category)) {
        return new List<Map<String,Object>>();
    }

    List<Interior_Product__c> products = [
        SELECT Id, Name, Product_Category__c, Room_Type__c, Unit_Price__c
        FROM Interior_Product__c
        WHERE Room_Type__c = :roomType
        AND Product_Category__c = :category
        ORDER BY Name
    ];

    Set<Id> productIds = new Set<Id>();
    for (Interior_Product__c p : products) {
        productIds.add(p.Id);
    }

    Map<Id, ContentDocumentLink> fileByProduct = new Map<Id, ContentDocumentLink>();

    if (!productIds.isEmpty()) {
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :productIds
        ]) {
            if (!fileByProduct.containsKey(cdl.LinkedEntityId)) {
                fileByProduct.put(cdl.LinkedEntityId, cdl);
            }
        }
    }

    List<Map<String,Object>> result = new List<Map<String,Object>>();

    for (Interior_Product__c p : products) {

        Map<String,Object> row = new Map<String,Object>();

        row.put('Id', p.Id);
        row.put('Name', p.Name);
        row.put('Room_Type__c', p.Room_Type__c);
        row.put('Product_Category__c', p.Product_Category__c);
        row.put('Unit_Price__c', p.Unit_Price__c);

        if (fileByProduct.containsKey(p.Id)) {

    Id versionId = fileByProduct.get(p.Id)
        .ContentDocument
        .LatestPublishedVersionId;

    String imageUrl =
    '/sfsites/c/sfc/servlet.shepherd/version/download/' + versionId;

    row.put('imageUrl', imageUrl);

} else {

    row.put('imageUrl',
        '/sfsites/c/resource/Default_Product_Image'
    );
}

        result.add(row);
    }

    return result;
}
}