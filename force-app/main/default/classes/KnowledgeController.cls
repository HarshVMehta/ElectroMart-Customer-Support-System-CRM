public with sharing class KnowledgeController {

    public class KnowledgeArticleDetails {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String summary;
        @AuraEnabled public String urlName;
        @AuraEnabled public String articleNumber;
        @AuraEnabled public Integer articleTotalViewCount;
        @AuraEnabled public String body;
    }
    
    /**
     * Get popular knowledge articles based on view count
     * @param limitCount - Number of articles to return
     * @return List of Knowledge articles
     */
    @AuraEnabled(cacheable=true)
    public static List<Knowledge__kav> getPopularArticles(Integer limitCount) {
        try {
            if (limitCount == null || limitCount <= 0) {
                limitCount = 6;
            }
            
            // Query published knowledge articles ordered by view count
            List<Knowledge__kav> articles = [
                SELECT Id, Title, Summary, UrlName, ArticleNumber, 
                       ArticleTotalViewCount
                FROM Knowledge__kav
                WHERE PublishStatus = 'Online' 
                AND Language = 'en_US'
                ORDER BY ArticleTotalViewCount DESC NULLS LAST
                LIMIT :limitCount
            ];
            
            return articles;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching articles: ' + e.getMessage());
        }
    }
    
    /**
     * Search knowledge articles by keyword
     * @param searchTerm - Search keyword
     * @param limitCount - Number of results to return
     * @return List of matching Knowledge articles
     */
    @AuraEnabled(cacheable=true)
    public static List<Knowledge__kav> searchArticles(String searchTerm, Integer limitCount) {
        try {
            if (String.isBlank(searchTerm)) {
                return new List<Knowledge__kav>();
            }
            
            if (limitCount == null || limitCount <= 0) {
                limitCount = 10;
            }
            
            String searchQuery = '%' + searchTerm + '%';
            
            List<Knowledge__kav> articles = [
                SELECT Id, Title, Summary, UrlName, ArticleNumber,
                       ArticleTotalViewCount
                FROM Knowledge__kav
                WHERE PublishStatus = 'Online'
                AND Language = 'en_US'
                AND (Title LIKE :searchQuery OR Summary LIKE :searchQuery)
                ORDER BY ArticleTotalViewCount DESC NULLS LAST
                LIMIT :limitCount
            ];
            
            return articles;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error searching articles: ' + e.getMessage());
        }
    }
    
    /**
     * Get articles by category
     * @param category - Product category
     * @param limitCount - Number of results to return
     * @return List of Knowledge articles
     */
    @AuraEnabled(cacheable=true)
    public static List<Knowledge__kav> getArticlesByCategory(String category, Integer limitCount) {
        try {
            if (String.isBlank(category)) {
                return new List<Knowledge__kav>();
            }
            
            if (limitCount == null || limitCount <= 0) {
                limitCount = 10;
            }

            String normalizedCategory = normalizeCategoryForField(category.trim());
            String fallbackKeyword = normalizeCategorySearchKeyword(category.trim());
            List<Knowledge__kav> articles = new List<Knowledge__kav>();

            Map<String, Schema.SObjectField> fieldMap = Knowledge__kav.SObjectType.getDescribe().fields.getMap();
            Boolean canUseCategoryField = fieldMap.containsKey('Category__c')
                && fieldMap.get('Category__c').getDescribe().isAccessible();

            if (canUseCategoryField) {
                String categorySoql =
                    'SELECT Id, Title, Summary, UrlName, ArticleNumber, ArticleTotalViewCount '
                    + 'FROM Knowledge__kav '
                    + 'WHERE PublishStatus = \'Online\' '
                    + 'AND Language = \'en_US\' '
                    + 'AND Category__c = :normalizedCategory '
                    + 'ORDER BY ArticleTotalViewCount DESC NULLS LAST '
                    + 'LIMIT :limitCount';

                articles = Database.query(categorySoql);
            }

            if (articles.isEmpty()) {
                articles = searchArticles(fallbackKeyword, limitCount);
            }
            
            return articles;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching category articles: ' + e.getMessage());
        }
    }

    /**
     * Get dynamic article counts for each product category.
     * Uses Category__c when available; falls back to keyword counts otherwise.
     */
    @AuraEnabled
    public static Map<String, Integer> getCategoryArticleCounts() {
        try {
            Map<String, Integer> countsByCategory = new Map<String, Integer>{
                'Mobile' => 0,
                'Laptop' => 0,
                'Television' => 0,
                'Home Appliance' => 0,
                'Warranty' => 0
            };

            Map<String, Schema.SObjectField> fieldMap = Knowledge__kav.SObjectType.getDescribe().fields.getMap();
            Boolean canUseCategoryField = fieldMap.containsKey('Category__c')
                && fieldMap.get('Category__c').getDescribe().isAccessible();

            List<String> canonicalCategories = new List<String>{
                'Mobile',
                'Laptop',
                'Television',
                'Home Appliance',
                'Warranty'
            };

            if (canUseCategoryField) {
                List<AggregateResult> groupedCounts = [
                    SELECT Category__c category, COUNT(Id) total
                    FROM Knowledge__kav
                    WHERE PublishStatus = 'Online'
                    AND Language = 'en_US'
                    GROUP BY Category__c
                ];

                for (AggregateResult groupedResult : groupedCounts) {
                    String rawCategory = String.valueOf(groupedResult.get('category'));
                    if (String.isBlank(rawCategory)) {
                        continue;
                    }

                    String category = normalizeCategoryForField(rawCategory);
                    if (!countsByCategory.containsKey(category)) {
                        continue;
                    }

                    Integer total = Integer.valueOf(String.valueOf(groupedResult.get('total')));
                    countsByCategory.put(category, countsByCategory.get(category) + total);
                }

                for (String categoryKey : canonicalCategories) {
                    if (countsByCategory.get(categoryKey) == 0) {
                        countsByCategory.put(categoryKey, countArticlesByKeyword(normalizeCategorySearchKeyword(categoryKey)));
                    }
                }

                return countsByCategory;
            }

            for (String categoryKey : canonicalCategories) {
                countsByCategory.put(categoryKey, countArticlesByKeyword(normalizeCategorySearchKeyword(categoryKey)));
            }

            return countsByCategory;

        } catch (Exception e) {
            throw new AuraHandledException('Error fetching category counts: ' + e.getMessage());
        }
    }

    /**
     * Get a single article with richer content for modal preview
     * @param articleVersionId - Knowledge article version Id (Knowledge__kav Id)
     * @return Rich article detail data
     */
    @AuraEnabled(cacheable=true)
    public static KnowledgeArticleDetails getArticleDetails(Id articleVersionId) {
        try {
            if (articleVersionId == null) {
                throw new AuraHandledException('Article Id is required');
            }

            Map<String, Schema.SObjectField> fieldMap = Knowledge__kav.SObjectType.getDescribe().fields.getMap();
            List<String> contentFields = resolveArticleContentFields(fieldMap);

            String soql = 'SELECT Id, Title, Summary, UrlName, ArticleNumber, ArticleTotalViewCount';
            for (String fieldName : contentFields) {
                soql += ', ' + fieldName;
            }

            soql += ' FROM Knowledge__kav'
                 + ' WHERE Id = :articleVersionId'
                 + ' AND PublishStatus = \'Online\''
                 + ' AND Language = \'en_US\''
                 + ' LIMIT 1';

            Knowledge__kav article = (Knowledge__kav) Database.query(soql);

            KnowledgeArticleDetails detail = new KnowledgeArticleDetails();
            detail.id = article.Id;
            detail.title = article.Title;
            detail.summary = article.Summary;
            detail.urlName = article.UrlName;
            detail.articleNumber = article.ArticleNumber;
            detail.articleTotalViewCount = Integer.valueOf(article.ArticleTotalViewCount);
            detail.body = extractFirstContentValue(article, contentFields);

            if (String.isBlank(detail.body) && String.isNotBlank(detail.summary)) {
                detail.body = detail.summary;
            }

            return detail;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching article details: ' + e.getMessage());
        }
    }

    private static List<String> resolveArticleContentFields(Map<String, Schema.SObjectField> fieldMap) {
        List<String> preferredFields = new List<String>{
            'Article_Body__c',
            'Body__c',
            'Content__c',
            'Details__c',
            'Description__c',
            'Answer__c',
            'Resolution__c',
            'Steps__c'
        };

        List<String> resolvedFields = new List<String>();

        for (String apiName : preferredFields) {
            if (fieldMap.containsKey(apiName) && fieldMap.get(apiName).getDescribe().isAccessible()) {
                resolvedFields.add(apiName);
            }
        }

        if (!resolvedFields.isEmpty()) {
            return resolvedFields;
        }

        for (String apiName : fieldMap.keySet()) {
            if (!apiName.endsWith('__c')) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(apiName).getDescribe();
            if (!fieldDescribe.isAccessible()) {
                continue;
            }

            if (fieldDescribe.getType() == Schema.DisplayType.TextArea ||
                fieldDescribe.isHtmlFormatted()) {
                resolvedFields.add(apiName);
            }
        }

        return resolvedFields;
    }

    private static String extractFirstContentValue(Knowledge__kav article, List<String> contentFields) {
        for (String fieldName : contentFields) {
            Object rawValue = article.get(fieldName);
            if (rawValue != null && String.isNotBlank(String.valueOf(rawValue))) {
                return String.valueOf(rawValue);
            }
        }

        return null;
    }

    private static Integer countArticlesByKeyword(String keyword) {
        String searchQuery = '%' + keyword + '%';

        return [
            SELECT COUNT()
            FROM Knowledge__kav
            WHERE PublishStatus = 'Online'
            AND Language = 'en_US'
            AND (Title LIKE :searchQuery OR Summary LIKE :searchQuery)
        ];
    }

    private static String normalizeCategoryForField(String category) {
        String key = category.toLowerCase().replace(' ', '');

        if (key == 'mobile' || key == 'mobiles' || key == 'smartphone' || key == 'smartphones' ||
            key == 'mobilephone' || key == 'mobilephones' || key == 'cellphone' || key == 'cellphones' ||
            key == 'phone' || key == 'phones') {
            return 'Mobile';
        }

        if (key == 'laptop' || key == 'laptops' || key == 'notebook' || key == 'notebooks') {
            return 'Laptop';
        }

        if (key == 'tv' || key == 'tvs' || key == 'television' || key == 'televisions' ||
            key == 'smarttv' || key == 'smarttvs' || key == 'ledtv' || key == 'ledtvs') {
            return 'Television';
        }

        if (key == 'appliance' || key == 'appliances' || key == 'homeappliance' || key == 'homeappliances') {
            return 'Home Appliance';
        }

        if (key == 'warranty' || key == 'warranties') {
            return 'Warranty';
        }

        return category;
    }

    private static String normalizeCategorySearchKeyword(String category) {
        String fieldValue = normalizeCategoryForField(category);

        if (fieldValue == 'Home Appliance') {
            return 'appliance';
        }

        if (fieldValue == 'Television') {
            return 'tv';
        }

        return fieldValue.toLowerCase();
    }
}