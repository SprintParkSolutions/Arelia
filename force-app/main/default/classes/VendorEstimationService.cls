public with sharing class VendorEstimationService {

    public class VendorEstimate {
        @AuraEnabled public String category;
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public Decimal estimatedAmount;
        @AuraEnabled public Decimal totalBudget;
        @AuraEnabled public Decimal usableBudget;
    }

    public class VendorTaskEstimate {
        @AuraEnabled public String taskName;
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public Decimal estimatedAmount;
    }

    // =====================================
    // 🔹 OPPORTUNITY ESTIMATION (FIXED)
    // =====================================
    @AuraEnabled
    public static List<VendorEstimate> estimateVendorsFromOpportunity(Id opportunityId) {

        Opportunity opp = [
            SELECT Name, Description, Supervisor_Estimated_Budget__c
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];

        Decimal originalBudget = opp.Supervisor_Estimated_Budget__c == null ? 0 : opp.Supervisor_Estimated_Budget__c;
        Decimal usableBudget = (originalBudget * 80) / 100;

        String prompt =
            'You are an expert interior budget planner.\n' +
            'Project: ' + opp.Name + '\n' +
            'Description: ' + opp.Description + '\n' +
            'Budget: ' + originalBudget + '\n\n' +
            'IMPORTANT RULES:\n' +
            '- Return ONLY JSON\n' +
            '- No explanation\n' +
            '- No text outside JSON\n' +
            '- Ensure total % = 100\n\n' +
            'FORMAT:\n' +
            '[{"category":"Furniture","percentage":40}]';

        Integer maxRetries = 2;
        List<Object> parsed;

        for(Integer i=0; i<=maxRetries; i++){

            try{
                HttpRequest req = new HttpRequest();
                req.setEndpoint('callout:OpenAI_API/v1/chat/completions');
                req.setMethod('POST');
                req.setHeader('Content-Type','application/json');

                req.setBody(JSON.serialize(new Map<String,Object>{
                    'model' => 'gpt-4o-mini',
                    'messages' => new List<Object>{
                        new Map<String,String>{
                            'role' => 'user',
                            'content' => prompt
                        }
                    }
                }));

                Http http = new Http();
                HttpResponse res = http.send(req);

                Map<String,Object> response =
                    (Map<String,Object>)JSON.deserializeUntyped(res.getBody());

                List<Object> choices = (List<Object>)response.get('choices');

                String content =
                    (String)((Map<String,Object>)
                    ((Map<String,Object>)choices[0]).get('message')).get('content');

                content = content.replace('```json','').replace('```','').trim();

                System.debug('AI RESPONSE ATTEMPT ' + i + ': ' + content);

                parsed = (List<Object>)JSON.deserializeUntyped(content);

                if(parsed != null && parsed.size() > 0){
                    break; // ✅ success
                }

            }catch(Exception e){
                System.debug('Retry ' + i + ' failed: ' + e.getMessage());
            }
        }

        // ❌ STILL FAILED → FALLBACK
        if(parsed == null || parsed.size() == 0){

            System.debug('⚠️ Using fallback estimation');

            parsed = new List<Object>{
                new Map<String,Object>{ 'category'=>'Furniture', 'percentage'=>30 },
                new Map<String,Object>{ 'category'=>'Lighting', 'percentage'=>20 },
                new Map<String,Object>{ 'category'=>'Flooring', 'percentage'=>20 },
                new Map<String,Object>{ 'category'=>'Paint', 'percentage'=>15 },
                new Map<String,Object>{ 'category'=>'Decor', 'percentage'=>15 }
            };
        }

        List<VendorEstimate> results = new List<VendorEstimate>();

        for(Object obj : parsed){

            Map<String,Object> row = (Map<String,Object>)obj;

            Decimal pct = Decimal.valueOf(String.valueOf(row.get('percentage')));

            VendorEstimate v = new VendorEstimate();
            v.category = (String)row.get('category');
            v.percentage = pct;
            v.estimatedAmount = (usableBudget * pct) / 100;
            v.totalBudget = originalBudget;
            v.usableBudget = usableBudget;

            results.add(v);
        }

        return results;
    }


    // =====================================
    // 🔹 IMAGE ESTIMATION (AI FULL)
    // =====================================
    @AuraEnabled
    public static List<VendorEstimate> estimateFromImages(List<Id> contentDocumentIds){

        List<String> images = new List<String>();

        for(Id docId : contentDocumentIds){

            ContentVersion cv = [
                SELECT VersionData
                FROM ContentVersion
                WHERE ContentDocumentId = :docId
                ORDER BY VersionNumber DESC
                LIMIT 1
            ];

            images.add('data:image/png;base64,' + EncodingUtil.base64Encode(cv.VersionData));
        }

        // 🔥 ULTRA SMART PROMPT
        String prompt =
            'You are a senior interior architect AI.\n' +
            'Analyze ALL uploaded design images together as ONE project.\n\n' +
            'DO NOT treat them separately.\n\n' +
            'Tasks:\n' +
            '1. Identify overall interior style\n' +
            '2. Estimate TOTAL PROJECT COST in INR\n' +
            '3. Allocate vendor categories realistically\n\n' +
            'RULES:\n' +
            '- Realistic pricing (India mid-premium)\n' +
            '- No random values\n' +
            '- Total % MUST = 100\n' +
            '- Return ONLY JSON\n\n' +
            'FORMAT:\n' +
            '{ "totalBudget":1000000, "usableBudget":800000, "vendors":[{"category":"Furniture","percentage":40}] }';

        List<Object> contentParts = new List<Object>();

        contentParts.add(new Map<String,Object>{
            'type' => 'text',
            'text' => prompt
        });

        for(String img : images){
            contentParts.add(new Map<String,Object>{
                'type' => 'image_url',
                'image_url' => new Map<String,Object>{
                    'url' => img
                }
            });
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:OpenAI_API/v1/chat/completions');
        req.setMethod('POST');
        req.setHeader('Content-Type','application/json');

        req.setBody(JSON.serialize(new Map<String,Object>{
            'model' => 'gpt-4o',
            'messages' => new List<Object>{
                new Map<String,Object>{
                    'role' => 'user',
                    'content' => contentParts
                }
            }
        }));

        Http http = new Http();
        HttpResponse res = http.send(req);

        Map<String,Object> response =
            (Map<String,Object>)JSON.deserializeUntyped(res.getBody());

        List<Object> choices = (List<Object>)response.get('choices');

        String content =
            (String)((Map<String,Object>)
            ((Map<String,Object>)choices[0]).get('message')).get('content');

        content = content.replace('```json','').replace('```','').trim();

        Map<String,Object> parsed =
            (Map<String,Object>)JSON.deserializeUntyped(content);

        Decimal totalBudget = Decimal.valueOf(String.valueOf(parsed.get('totalBudget')));
        Decimal usableBudget = Decimal.valueOf(String.valueOf(parsed.get('usableBudget')));

        List<Object> vendors = (List<Object>)parsed.get('vendors');

        List<VendorEstimate> results = new List<VendorEstimate>();

        for(Object obj : vendors){

            Map<String,Object> row = (Map<String,Object>)obj;

            Decimal pct = Decimal.valueOf(String.valueOf(row.get('percentage')));

            VendorEstimate v = new VendorEstimate();
            v.category = (String)row.get('category');
            v.percentage = pct;
            v.estimatedAmount = (usableBudget * pct) / 100;
            v.totalBudget = totalBudget;
            v.usableBudget = usableBudget;

            results.add(v);
        }

        return results;
    }


    // =====================================
    // 🔹 TASK ESTIMATION
    // =====================================
    @AuraEnabled
    public static List<VendorTaskEstimate> estimateTasksForVendor(String vendorCategory, Decimal vendorBudget){

        String prompt =
            'Break vendor "' + vendorCategory + '" into tasks.\n' +
            'Return ONLY JSON:\n' +
            '[{"task":"Work","percentage":40}]';

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:OpenAI_API/v1/chat/completions');
        req.setMethod('POST');
        req.setHeader('Content-Type','application/json');

        req.setBody(JSON.serialize(new Map<String,Object>{
            'model' => 'gpt-4o-mini',
            'messages' => new List<Object>{
                new Map<String,String>{
                    'role' => 'user',
                    'content' => prompt
                }
            }
        }));

        Http http = new Http();
        HttpResponse res = http.send(req);

        Map<String,Object> response =
            (Map<String,Object>)JSON.deserializeUntyped(res.getBody());

        List<Object> choices = (List<Object>)response.get('choices');

        String content =
            (String)((Map<String,Object>)
            ((Map<String,Object>)choices[0]).get('message')).get('content');

        content = content.replace('```json','').replace('```','').trim();

        System.debug('TASK AI RESPONSE: ' + content);

        List<Object> parsed =
            (List<Object>)JSON.deserializeUntyped(content);

        List<VendorTaskEstimate> results = new List<VendorTaskEstimate>();

        for(Object obj : parsed){

            Map<String,Object> row = (Map<String,Object>)obj;

            Decimal pct = Decimal.valueOf(String.valueOf(row.get('percentage')));

            VendorTaskEstimate t = new VendorTaskEstimate();
            t.taskName = (String)row.get('task');
            t.percentage = pct;
            t.estimatedAmount = (vendorBudget * pct)/100;

            results.add(t);
        }

        return results;
    }

    // =====================================
    // 🔹 PROFORMA GENERATION (AI)
    // =====================================
    @AuraEnabled
    public static Map<String,Object> generateProforma(List<VendorEstimate> vendors){

        try{

            String prompt =
            'You are a SENIOR INTERIOR DESIGN COST ESTIMATOR (India).\n\n' +

            'INPUT:\n' + JSON.serialize(vendors) + '\n\n' +

            'STRICT INSTRUCTIONS:\n' +
            '- Generate a REALISTIC BOQ (Bill of Quantity)\n' +
            '- Every category MUST have 6 to 12 items (VERY IMPORTANT)\n' +
            '- Items must be PRACTICAL and USED in real interiors\n' +
            '- DO NOT generate generic items like "Work"\n' +
            '- Use PROPER ITEM NAMES\n' +
            '- Use realistic quantities (not all 1)\n' +
            '- Ensure amount = qty × rate\n' +
            '- Distribute budget logically\n\n' +

            'CATEGORIES MUST INCLUDE (if budget allows):\n' +
            'Furniture, Kitchen, Bedroom, Living Room, Electrical, Lighting, Wall Finishes, Decor\n\n' +

            'EXAMPLE ITEMS:\n' +
            '- Bed with headboard\n' +
            '- Wardrobe sliding\n' +
            '- TV panel with laminate\n' +
            '- False ceiling gypsum\n' +
            '- Cove lighting LED strip\n' +
            '- Modular kitchen cabinets\n' +
            '- Dining table set\n' +
            '- Curtains\n' +
            '- Wall paint / texture\n\n' +

            'OUTPUT STRICT JSON ONLY:\n' +
            '{' +
            '"sections":[' +
                '{' +
                    '"name":"Furniture",' +
                    '"subtotal":250000,' +
                    '"items":[' +
                        '{"item":"Bed","qty":1,"rate":50000,"amount":50000}' +
                    ']' +
                '}' +
            '],' +
            '"total":800000,' +
            '"gst":144000,' +
            '"grandTotal":944000' +
            '}';

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:OpenAI_API/v1/chat/completions');
            req.setMethod('POST');
            req.setHeader('Content-Type','application/json');

            req.setBody(JSON.serialize(new Map<String,Object>{

            'model' => 'gpt-4o',

            'messages' => new List<Object>{
                new Map<String,Object>{
                    'role' => 'user',
                    'content' => prompt
                }
            },

            'response_format' => new Map<String,Object>{
                'type' => 'json_object'
            },

            'temperature' => 0.5,

            'max_tokens' => 12000
        }));

            Http http = new Http();
            HttpResponse res = http.send(req);

            System.debug('AI RAW RESPONSE: ' + res.getBody());

            Map<String,Object> response =
                (Map<String,Object>)JSON.deserializeUntyped(res.getBody());

            List<Object> choices = (List<Object>)response.get('choices');

            if(choices == null || choices.isEmpty()){
                return generateFallback(vendors);
            }

            String content =
                (String)((Map<String,Object>)
                ((Map<String,Object>)choices[0]).get('message')).get('content');

            content = content.replace('```json','').replace('```','').trim();

            // 🔥 Extract JSON safely
            Integer start = content.indexOf('{');
            Integer endIndex = content.lastIndexOf('}');

            if(start >= 0 && endIndex > start){
                content = content.substring(start, endIndex + 1);
            }

            Map<String,Object> parsed =
                (Map<String,Object>)JSON.deserializeUntyped(content);

            if(parsed == null || !parsed.containsKey('sections')){
                return generateFallback(vendors);
            }

            return parsed;

        }catch(Exception e){
            System.debug('PROFORMA ERROR: ' + e.getMessage());
            return generateFallback(vendors);
        }
    }

    @AuraEnabled
public static Map<String,Object> generateProformaFromImages(
    List<Id> contentDocumentIds,
    List<VendorEstimate> vendors
){

    try{

        List<Object> contentParts = new List<Object>();

        String prompt =

        'You are a professional interior BOQ estimation engine.\n\n' +

        'Analyze all uploaded files together.\n' +
        'The uploaded files may include:\n' +
        '- Architectural floor plans\n' +
        '- Electrical layouts\n' +
        '- Interior design renders\n' +
        '- Furniture layouts\n\n' +

        'Your responsibility is to generate a REALISTIC INTERIOR EXECUTION PROFORMA.\n\n' +

        'IMPORTANT RULES:\n' +

        '- Analyze the uploaded designs visually\n' +
        '- Detect all visible furniture, finishes, decor, lighting, wall treatments and fixtures dynamically\n' +
        '- Detect approximate room dimensions from floor plans\n' +
        '- Detect flooring areas\n' +
        '- Detect wall panel areas\n' +
        '- Detect false ceiling areas\n' +
        '- Detect electrical points from electrical layout\n' +
        '- Detect plumbing fixtures from bathroom/kitchen layouts\n' +
        '- Generate only items actually relevant to uploaded designs\n' +
        '- DO NOT generate random items\n' +
        '- DO NOT assume all rooms exist\n' +
        '- DO NOT force categories\n' +
        '- DO NOT generate placeholder items\n' +
        '- DO NOT generate generic items like "Furniture Work"\n' +
        '- Generate practical BOQ like real contractors\n' +
        '- Use realistic Indian market pricing\n' +
        '- Estimate quantities dynamically based on detected areas\n' +
        '- Include material cost\n' +
        '- Include labor cost\n' +
        '- Include GST\n' +
        '- Calculate amount realistically\n\n' +

        'IMPORTANT:\n' +
        '- Output must be highly detailed\n' +
        '- Output must be room-wise\n' +
        '- Output must be realistic execution BOQ\n' +
        '- Output should resemble an actual contractor estimate\n\n' +

        'Return STRICT JSON ONLY.\n\n' +

        'JSON FORMAT:\n' +

        '{' +

        '"projectSummary":{' +
        '"projectType":"",' +
        '"style":"",' +
        '"totalAreaSqft":0,' +
        '"estimatedDuration":""' +
        '},' +

        '"sections":[' +

        '{' +
        '"room":"",' +
        '"category":"",' +
        '"subtotal":0,' +
        '"items":[' +

        '{' +
        '"item":"",' +
        '"description":"",' +
        '"unit":"",' +
        '"qty":0,' +
        '"areaSqft":0,' +
        '"materialCost":0,' +
        '"laborCost":0,' +
        '"gst":0,' +
        '"amount":0' +
        '}' +

        ']' +
        '}' +

        '],' +

        '"totalMaterialCost":0,' +
        '"totalLaborCost":0,' +
        '"totalGST":0,' +
        '"grandTotal":0' +

        '}';

        contentParts.add(new Map<String,Object>{
            'type' => 'text',
            'text' => prompt
        });

        for(Id docId : contentDocumentIds){

            ContentVersion cv = [
                SELECT VersionData
                FROM ContentVersion
                WHERE ContentDocumentId = :docId
                ORDER BY VersionNumber DESC
                LIMIT 1
            ];

            String img = 'data:image/png;base64,' + EncodingUtil.base64Encode(cv.VersionData);

            contentParts.add(new Map<String,Object>{
                'type' => 'image_url',
                'image_url' => new Map<String,Object>{
                    'url' => img
                }
            });
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:OpenAI_API/v1/chat/completions');
        req.setMethod('POST');
        req.setHeader('Content-Type','application/json');

        req.setBody(JSON.serialize(new Map<String,Object>{
        'model' => 'gpt-4o',

        'messages' => new List<Object>{
            new Map<String,Object>{
                'role' => 'user',
                'content' => contentParts
            }
        },

        // 🔥 IMPORTANT
        'response_format' => new Map<String,Object>{
            'type' => 'json_object'
        },

        'temperature' => 0.5,

        // 🔥 IMPORTANT
        'max_tokens' => 12000
    }));
        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('AI IMAGE PROFORMA: ' + res.getBody());

        Map<String,Object> response =
            (Map<String,Object>)JSON.deserializeUntyped(res.getBody());

        List<Object> choices = (List<Object>)response.get('choices');

        if(choices == null || choices.isEmpty()){
            return generateFallback(vendors);
        }

        String content =
            (String)((Map<String,Object>)
            ((Map<String,Object>)choices[0]).get('message')).get('content');

        content = content.replace('```json','').replace('```','').trim();

        Integer startIndex = content.indexOf('{');
        Integer endIndex = content.lastIndexOf('}');

        if(startIndex >= 0 && endIndex > startIndex){
            content = content.substring(startIndex, endIndex + 1);
        }

        Map<String,Object> parsed =
            (Map<String,Object>)JSON.deserializeUntyped(content);

        if(parsed == null || !parsed.containsKey('sections')){
            return generateFallback(vendors);
        }

        return parsed;

    }catch(Exception e){
        System.debug('IMAGE PROFORMA ERROR: ' + e.getMessage());
        return generateFallback(vendors);
    }
}
    
    private static Map<String,Object> generateFallback(List<VendorEstimate> vendors){

    List<Map<String,Object>> sections = new List<Map<String,Object>>();
    Decimal total = 0;

    for(VendorEstimate v : vendors){

        List<Map<String,Object>> items = new List<Map<String,Object>>();

        Decimal itemBudget = v.estimatedAmount / 3;

        items.add(new Map<String,Object>{
            'item' => v.category + ' Work',
            'qty' => 1,
            'rate' => itemBudget,
            'amount' => itemBudget
        });

        items.add(new Map<String,Object>{
            'item' => v.category + ' Materials',
            'qty' => 1,
            'rate' => itemBudget,
            'amount' => itemBudget
        });

        items.add(new Map<String,Object>{
            'item' => v.category + ' Installation',
            'qty' => 1,
            'rate' => itemBudget,
            'amount' => itemBudget
        });

        sections.add(new Map<String,Object>{
            'name' => v.category,
            'items' => items
        });

        total += v.estimatedAmount;
    }

    Decimal gst = total * 0.18;

    return new Map<String,Object>{
        'sections' => sections,
        'total' => total,
        'gst' => gst,
        'grandTotal' => total + gst
    };
}
            
}