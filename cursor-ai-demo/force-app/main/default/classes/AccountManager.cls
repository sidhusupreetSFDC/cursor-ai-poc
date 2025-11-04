/**
 * AccountManager - Handles account operations
 * This class has INTENTIONAL ISSUES for AI to detect:
 * 1. SOQL in loop
 * 2. DML in loop
 * 3. No error handling
 * 4. Missing sharing rules
 * 5. No bulk processing
 * 6. Hardcoded values
 */
public class AccountManager {
    
    // Issue: No sharing rules specified
    public static void updateAccountNames(List<Id> accountIds) {
        // Issue: SOQL in loop
        for(Id accId : accountIds) {
            Account acc = [SELECT Id, Name FROM Account WHERE Id = :accId];
            acc.Name = acc.Name + ' - Updated';
            // Issue: DML in loop
            update acc;
        }
    }
    
    // Issue: Hardcoded API key
    private static final String API_KEY = 'sk_live_1234567890abcdef';
    
    // Issue: No input validation
    public static Account createAccount(String name) {
        Account acc = new Account(Name = name);
        insert acc;
        return acc;
    }
    
    // Issue: SOSL in loop, no error handling
    public static List<Account> searchAccounts(List<String> searchTerms) {
        List<Account> results = new List<Account>();
        for(String term : searchTerms) {
            List<List<SObject>> searchResults = [FIND :term IN ALL FIELDS RETURNING Account(Id, Name)];
            results.addAll(searchResults[0]);
        }
        return results;
    }
    
    // Issue: No field-level security check
    public static void updateAccountIndustry(Id accountId, String industry) {
        Account acc = [SELECT Id FROM Account WHERE Id = :accountId];
        acc.Industry = industry;
        update acc;
    }
    
    // Issue: Potential null pointer, no bulkification
    public static void linkContactsToAccount(List<Contact> contacts, Id accountId) {
        for(Contact con : contacts) {
            con.AccountId = accountId;
            update con;
        }
    }
}