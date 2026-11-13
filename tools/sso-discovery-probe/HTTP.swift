import Foundation

final class TrustedRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock=NSLock()
    private var counts: [Int:Int] = [:]
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {
        lock.lock(); counts[task.taskIdentifier, default:0] += 1; let allowedCount=counts[task.taskIdentifier, default:0] <= 12; lock.unlock()
        guard allowedCount, let url=request.url, url.scheme == "https", let host=url.host,
              host == "battle.net" || host.hasSuffix(".battle.net") else { completionHandler(nil); return }
        completionHandler(request)
    }
}
func execute() async {
    do {
        guard let raw = try LaunchOptions(gameKey:"WoW").storedToken(), let ticket=LoginToken(raw) else {
            print("No well-formed current WoW login entry. No request made.");return
        }
        let config=URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=12;config.timeoutIntervalForResource=25
        config.httpShouldSetCookies=true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let client=URLSession(configuration:config,delegate:TrustedRedirects(),delegateQueue:nil)
        defer { client.invalidateAndCancel() }
        var initial=URLComponents(string:"https://account.battle.net/login/sso")!
        initial.queryItems=[URLQueryItem(name:"token",value:ticket.value),URLQueryItem(name:"ref",value:"https://account.battle.net/games")]
        let (_,landing)=try await client.data(from:initial.url!)
        let landingHTTP=(landing as? HTTPURLResponse)?.statusCode ?? 0
        print("SSO landing HTTP status:",landingHTTP)
        print("SSO landing is a login path:",landing.url?.path.contains("/login") == true)
        let (_,oauthLanding)=try await client.data(from:URL(string:"https://account.battle.net/oauth2/authorization/account-settings")!)
        print("Account OAuth landing HTTP status:",(oauthLanding as? HTTPURLResponse)?.statusCode ?? 0)
        print("Account OAuth settled on login path:",oauthLanding.url?.path.contains("/login") == true)
        var stateRequest=URLRequest(url:URL(string:"https://account.battle.net/api/")!)
        stateRequest.httpMethod="POST"
        let (stateData,stateResponse)=try await client.data(for:stateRequest)
        print("Account-state HTTP status:",(stateResponse as? HTTPURLResponse)?.statusCode ?? 0)
        let state=(try? JSONSerialization.jsonObject(with:stateData)) as? [String:Any]
        let signedIn=state?["authenticated"] as? Bool == true
        let owner=state?["accountId"].map { String(describing:$0) }
        let matches=signedIn && owner==ticket.accountID
        print("Authenticated as ticket owner:",matches)
        guard matches else { print("Game ticket did not establish an owner-verified account-website session in this test.");return }
        let (data,response)=try await client.data(from:URL(string:"https://account.battle.net/api/games-and-subs")!)
        print("Catalogue HTTP status:",(response as? HTTPURLResponse)?.statusCode ?? 0)
        let payload=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        print("Licence array returned:",payload?["gameAccounts"] is [[String:Any]])
    } catch {
        // Do not print errors: Foundation's error userInfo can include credential URLs.
        print("SSO test failed before a verified result. No error URLs or credential values displayed.")
    }
}
Task { await execute(); exit(0) }
dispatchMain()
