//
//  SubscriptionListVC.swift
//  GaurdianDrive
//
//  Created by KETAN on 05/02/26.
//

import UIKit
import StoreKit
import SwiftUI

class SubscriptionViewState: ObservableObject {
    @Published var isMonthlySelected = true
    @Published var selectedIndex = 99
    @Published var arrSubsDataMonthly: [SubscriptionModel] = []
    @Published var arrSubsDataYearly: [SubscriptionModel] = []
}

class SubscriptionListVC: UIViewController {

    //Outlets....
    @IBOutlet var btnMonthly: UIButton!
    @IBOutlet var btnYearly: UIButton!
    @IBOutlet weak var viewForPaymentDetails: UIView!
    @IBOutlet var collViewPlanList: UICollectionView!

    //Variables..
    var isMonthlySelected = true
    var arrSubsDataMonthly = [SubscriptionModel]()
    var arrSubsDataYearly = [SubscriptionModel]()
    var selectedIndex = 99
    
    var viewState = SubscriptionViewState()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.initialization()
        self.setupSwiftUIView()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.setHidesBackButton(true, animated: true)

        //Hide tabbar code...
        self.tabBarController?.tabBar.isHidden = true
        if rootTab.cons_bottomBar_height != nil{
            rootTab.cons_bottomBar_height.constant = 0
            rootTab.viewBottomTabMain.isHidden = true
        }
    }
//    override func viewWillDisappear(_ animated: Bool) {
//        SKPaymentQueue.default().remove(self)
//        self.productsRequest.delegate = nil
//        self.productsRequest.cancel()
//    }
//    deinit {
//        SKPaymentQueue.default().remove(self)
//    }
}

//MARK: - Initialisation...
extension SubscriptionListVC
{
    func initialization() {
        
        self.collViewPlanList.register(UINib(nibName: "CellForPlans", bundle: nil), forCellWithReuseIdentifier: "CellForPlans")

        self.arrSubsDataMonthly.removeAll()
        self.arrSubsDataYearly.removeAll()
        self.setupAllInAppPurchaseProducts()

        // ✅ IAP Codes
        self.allSubscriptionMehodAndResponse()

    }
    
    func setupAllInAppPurchaseProducts()
    {
        let arry4Data1 = [["name":"Basic","productIdentifry":oneChild_1Month,"price":"$6.99","childCount":"1","yearly":"$74.99"],["name":"Family2","productIdentifry":twoChild_1Month,"price":"$7.99","childCount":"2","yearly":"$84.99"],["name":"Family3","productIdentifry":threeChild_1Month,"price":"$8.99","childCount":"3","yearly":"$94.99"],["name":"Family4","productIdentifry":fourChild_1Month,"price":"$9.99","childCount":"4","yearly":"$104.99"]]
        let arry4Data2 = [["name":"Basic","productIdentifry":oneChild_Yearly,"price":"$74.99","childCount":"1"],["name":"Family2","productIdentifry":twoChild_Yearly,"price":"$84.99","childCount":"2"],["name":"Family3","productIdentifry":threeChild_Yearly,"price":"$94.99","childCount":"3"],["name":"Family4","productIdentifry":fourChild_Yearly,"price":"$104.99","childCount":"4"]]
        
        self.arrSubsDataMonthly = arry4Data1.map { SubscriptionModel(dictData: $0 as NSDictionary) }
        self.arrSubsDataYearly  = arry4Data2.map { SubscriptionModel(dictData: $0 as NSDictionary) }
        
        self.viewState.arrSubsDataMonthly = self.arrSubsDataMonthly
        self.viewState.arrSubsDataYearly = self.arrSubsDataYearly
        self.viewState.isMonthlySelected = self.isMonthlySelected
        self.viewState.selectedIndex = self.selectedIndex
        
        self.collViewPlanList?.reloadData()
    }
    
    //IAP structures and call back...
    func allSubscriptionMehodAndResponse()
    {
        IAPManager.shared.onPurchaseSuccess = { [weak self] productId, transactionId, originalTransactionId, expiry in
            guard let self = self else { return }

            print("✅ SUCCESS:", productId, transactionId, originalTransactionId ,expiry as Any)

            let childCount = self.getChildCount(productId: productId)
            appDelegate.showHud()
            self.apiCallForSubscription(
                aTransactionID: originalTransactionId,
                aChildCount: childCount,
                aBunddleID:"org.app.GaurdianDrive"
            )
        }
        
        IAPManager.shared.onRestoreSuccess = { [weak self] productId, transactionId, originalTransactionId, expiry in
            guard let self = self else { return }

            print("♻️ RESTORE SUCCESS:", productId, transactionId, originalTransactionId, expiry as Any)

            let childCount = self.getChildCount(productId: productId)
            
            appDelegate.showHud()

            self.apiCallForSubscription(
                aTransactionID: originalTransactionId,
                aChildCount: childCount,
                aBunddleID: "org.app.GaurdianDrive"
            )
        }

        IAPManager.shared.onPurchaseFailed = { error in
            appDelegate.hideHud()
            print("❌ FAILED:", error)
        }

        // ✅ Fetch Products (async)

        Task {
            await IAPManager.shared.fetchProducts(ids: [
                oneChild_1Month,
                twoChild_1Month,
                threeChild_1Month,
                fourChild_1Month,
                oneChild_Yearly,
                twoChild_Yearly,
                threeChild_Yearly,
                fourChild_Yearly
            ])

            print("Products loaded:", IAPManager.shared.products.count)
            self.applyStorePrices(IAPManager.shared.products)
        }
    }

    /// Shows the App Store's own price for the user's storefront (e.g. ₹ in India) on
    /// every plan card, monthly and yearly. The USD strings set in
    /// `setupAllInAppPurchaseProducts()` stay as the fallback if products didn't load.
    /// Display only: purchasing still uses the same product ids.
    func applyStorePrices(_ products: [Product]) {
        guard !products.isEmpty else { return }
        var priceById = [String: String]()
        for product in products {
            priceById[product.id] = product.displayPrice
        }

        for plan in self.arrSubsDataYearly {
            if let price = priceById[plan.productIdentifry] {
                plan.price = price
            }
        }
        for plan in self.arrSubsDataMonthly {
            if let price = priceById[plan.productIdentifry] {
                plan.price = price
            }
            // "or ₹X /year" line on the monthly card: the yearly plan for the same child count.
            if let yearlyPlan = self.arrSubsDataYearly.first(where: { $0.childCount == plan.childCount }),
               let yearlyPrice = priceById[yearlyPlan.productIdentifry] {
                plan.yearly = yearlyPrice
            }
        }

        // Re-assign so the SwiftUI cards redraw with the new prices.
        self.viewState.arrSubsDataMonthly = self.arrSubsDataMonthly
        self.viewState.arrSubsDataYearly = self.arrSubsDataYearly
        self.collViewPlanList?.reloadData()
    }
    
    func getChildCount(productId: String) -> String {

        if let monthly = arrSubsDataMonthly.first(where: { $0.productIdentifry == productId }) {
            return monthly.childCount
        }

        if let yearly = arrSubsDataYearly.first(where: { $0.productIdentifry == productId }) {
            return yearly.childCount
        }

        return ""
    }
    
    func setupSwiftUIView() {
        self.view.subviews.forEach { $0.isHidden = true }
        self.view.backgroundColor = .white
        
        let swiftUIView = SubscriptionHostView(
            viewState: self.viewState,
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onPurchase: { [weak self] in
                self?.handleSwiftUIPurchase()
            },
            onRestore: { [weak self] in
                self?.tapToRestore(UIButton())
            },
            onTerms: {
                if let url = URL(string: WebURL.TERMHTML) {
                    UIApplication.shared.open(url)
                }
            },
            onPrivacy: {
                if let url = URL(string: WebURL.PrivacypolicyHTML) {
                    UIApplication.shared.open(url)
                }
            }
        )
        
        let hostingController = UIHostingController(rootView: swiftUIView)
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.view.backgroundColor = .clear
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }
    
    func handleSwiftUIPurchase() {
        self.isMonthlySelected = self.viewState.isMonthlySelected
        self.selectedIndex = self.viewState.selectedIndex
        self.tapToPurchase(UIButton())
    }
}

struct SubscriptionHostView: View {
    @ObservedObject var viewState: SubscriptionViewState
    var onBack: () -> Void
    var onPurchase: () -> Void
    var onRestore: () -> Void
    var onTerms: () -> Void
    var onPrivacy: () -> Void
    
    var body: some View {
        PremiumSubscriptionView(
            isMonthlySelected: $viewState.isMonthlySelected,
            selectedIndex: $viewState.selectedIndex,
            arrSubsDataMonthly: viewState.arrSubsDataMonthly,
            arrSubsDataYearly: viewState.arrSubsDataYearly,
            onBack: onBack,
            onRestoreTop: onRestore,
            onPurchase: onPurchase,
            onRestoreBottom: onRestore,
            onTerms: onTerms,
            onPrivacy: onPrivacy
        )
    }
}

//MARK: - Click Events.....
extension SubscriptionListVC
{
    @IBAction func tapToBack(_ sender: UIControl) {
        self.navigationController?.popViewController(animated: true)
    }
    @IBAction func tapToPurchase(_ sender: UIButton) {
        self.view.endEditing(true)

           if selectedIndex == 99 {
               popupAlert(title: "Select Plan",
                          message: "Please select a subscription plan first.",
                          actionTitles: ["OK"],
                          actions: [{ _ in }, nil])
               return
           }

           let productID = isMonthlySelected
               ? arrSubsDataMonthly[selectedIndex].productIdentifry
               : arrSubsDataYearly[selectedIndex].productIdentifry

           appDelegate.showHud()

           Task {
               await IAPManager.shared.purchase(productId: productID)
           }
        
//        if self.selectedIndex == 99 {
//            popupAlert(title: "Select Plan", message: "Please select a subscription plan first.", actionTitles: ["OK"], actions: [{ _ in }, nil])
//            return
//        }
//
//        if self.iapProducts.count > 0{
//            let productID1 =  (self.isMonthlySelected) ? self.arrSubsDataMonthly[self.selectedIndex].productIdentifry : self.arrSubsDataYearly[self.selectedIndex].productIdentifry
//            appDelegate.showHud()
//            self.setProductPurchase(strProductId: productID1)
//        }else
//        {
//            self.popupAlert(
//                title: "Error",
//                message: "Something went wrong. Please try again later.",
//                actionTitles: ["OK"],
//                actions: [{ action1 in
//                }, nil]
//            )
//        }
    }
    @IBAction func tapToRestore(_ sender: UIButton) {
        isConnectedToNetwork1 { isConnected in
                if isConnected {
                    appDelegate.showHud()
                    Task {
                        await IAPManager.shared.restorePurchases()
                    }
                }
            }
    }
    @IBAction func tapToMonthly(_ sender: UIButton) {
        if !self.isMonthlySelected
        {
            self.setupMonthYearSegmentSelectionWith(isMonth: true, aSelectedBtn: self.btnMonthly, aNoSelectBtn: self.btnYearly)
        }
    }
    @IBAction func tapToYearly(_ sender: UIButton) {
        if self.isMonthlySelected
        {
            self.setupMonthYearSegmentSelectionWith(isMonth: false, aSelectedBtn: self.btnYearly, aNoSelectBtn: self.btnMonthly)
        }
    }
    @IBAction func tapToCloseInfoPage(_ sender: UIButton) {
        self.viewForPaymentDetails.isHidden = true
    }
    @IBAction func tapToTermsAndPolicy(_ sender: UIControl) {
        let objWebViewCommonVC = self.storyboard?.instantiateViewController(withIdentifier:"WebViewCommonVC" ) as! WebViewCommonVC
        objWebViewCommonVC.strTitle = "Terms and Policy"
        self.navigationController?.pushViewController(objWebViewCommonVC, animated: true)
    }
    
    func setupMonthYearSegmentSelectionWith(isMonth:Bool,aSelectedBtn:UIButton,aNoSelectBtn:UIButton)
    {
        self.selectedIndex = 99
        self.isMonthlySelected = isMonth
        aSelectedBtn.setTitleColor(UIColor.white, for: .normal)
        aSelectedBtn.backgroundColor = UIColor.init(named:"AppDarkBlue")!
        aNoSelectBtn.backgroundColor = UIColor.white
        aNoSelectBtn.setTitleColor(UIColor.init(named:"AppDarkBlue")!, for: .normal)
        self.collViewPlanList?.reloadData()
    }
}

//MARK: - In-app Purcahse Delegates....
//extension SubscriptionListVC: SKProductsRequestDelegate,SKPaymentTransactionObserver,SKRequestDelegate
//{
//    // MARK: - FETCH AVAILABLE IAP PRODUCTS
//    func fetchAvailableProducts()  {
//
//        appDelegate.showHud(isWhiteBG: true)
//        // Put here your IAP Products ID's
//        let productIdentifiers = NSSet(objects:
//          oneChild_1Month,twoChild_1Month,threeChild_1Month,fourChild_1Month,oneChild_Yearly,twoChild_Yearly,threeChild_Yearly,fourChild_Yearly
//        )
//        productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers as! Set<String>)
//        productsRequest.delegate = self
//        productsRequest.start()
//    }
   
//    //MARK: - REQUEST IAP PRODUCTS
//    func productsRequest (_ request:SKProductsRequest, didReceive response:SKProductsResponse) {
//
//        print("Valid products count:", response.products.count)
//        print("Invalid products:", response.invalidProductIdentifiers)
//
//        if (response.products.count > 0) {
//            iapProducts = response.products
//            print(iapProducts)
//
////            let numberFormatter = NumberFormatter()
////            numberFormatter.formatterBehavior = .behavior10_4
////            numberFormatter.numberStyle = .currency
////
////            for productDetails in iapProducts
////            {
////                //let productDetails = iapProducts[i]
////                // Get its price from iTunes Connect
////                numberFormatter.locale = productDetails.priceLocale
////                let productPrice = numberFormatter.string(from: productDetails.price)
////                let productTitle = productDetails.localizedTitle
////                let productModel = SubscriptionModel()
////                productModel.name = productTitle
////                productModel.price = productPrice!
////                productModel.productIdentifry = productDetails.productIdentifier
////                let allowedCharset = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ""))
////                let filteredText = String(productPrice!.unicodeScalars.filter(allowedCharset.contains))
////                productModel.sortPrice = Int(filteredText)!
////                arrSubscriptionData.append(productModel)
////            }
////
////            self.collViewPlanList.reloadData()
//        }
//        appDelegate.hideHud()
//    }
//    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
//
//        for trans in transactions {
//
//
//            guard let transactionId = trans.transactionIdentifier ??
//                                      trans.original?.transactionIdentifier else {
//                SKPaymentQueue.default().finishTransaction(trans)
//                continue
//            }
//
//            if handledTransactionIDs.contains(transactionId) {
//                SKPaymentQueue.default().finishTransaction(trans)
//                continue
//            }
//
//            switch trans.transactionState {
//
//            case .purchased:
//                handledTransactionIDs.insert(transactionId)
//
//                print("✅ Purchased:", transactionId)
//                let productId = trans.original?.payment.productIdentifier ?? trans.payment.productIdentifier
//
//                // 👉 your success logic
//                var childCount = ""
//                if isMonthlySelected
//                {
//                    childCount = arrSubsDataMonthly.first(where: {$0.productIdentifry == productId})?.childCount ?? ""
//                }else {
//                    childCount = arrSubsDataYearly.first(where: {$0.productIdentifry == productId})?.childCount ?? ""
//                }
//               self.apiCallForSubscription(aTransactionID: transactionId, aChildCount: childCount, aBunddleID: productId)
//
//                SKPaymentQueue.default().finishTransaction(trans)
//                appDelegate.hideHud()
//
//            case .restored:
//                handledTransactionIDs.insert(transactionId)
//
//                let productId = trans.original?.payment.productIdentifier ?? trans.payment.productIdentifier
//                print("♻️ Restored:", transactionId, productId)
//
//                // 👉 your restore logic
//                var childCount = ""
//                if isMonthlySelected
//                {
//                    childCount = arrSubsDataMonthly.first(where: {$0.productIdentifry == productId})?.childCount ?? ""
//                }else {
//                    childCount = arrSubsDataYearly.first(where: {$0.productIdentifry == productId})?.childCount ?? ""
//                }
//               self.apiCallForSubscription(aTransactionID: transactionId, aChildCount: childCount, aBunddleID: productId)
//                SKPaymentQueue.default().finishTransaction(trans)
//                appDelegate.hideHud()
//
//            case .failed:
//                if let error = trans.error as? SKError,
//                   error.code != .paymentCancelled {
//                    print("❌ Error:", error.localizedDescription)
//                }
//
//                SKPaymentQueue.default().finishTransaction(trans)
//                appDelegate.hideHud()
//
//            case .purchasing:
//                break
//
//            case .deferred:
//                appDelegate.hideHud()
//
//            @unknown default:
//                break
//            }
//        }
//    }
//    // MARK: - IAP PAYMENT QUEUE
//    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
//
//        //IJProgressView.shared.showProgressView(view)
//        for transaction:AnyObject in transactions {
//            if let trans = transaction as? SKPaymentTransaction {
//
//                switch trans.transactionState {
//                case .purchasing:
//                          break
//                case .purchased:
//                    //Get data from backend and set user free..
////                    self.getDataOfPurchaseFromApi()
////                    let transactionId = transaction.transactionIdentifier ?? ""
////                    let productId = transaction.payment.productIdentifier
//                    let transactionId = trans.transactionIdentifier ?? ""
//                    let productId = trans.payment.productIdentifier
//                    print("STATE:", trans.transactionState.rawValue)
//                    print("PRODUCT:", trans.payment.productIdentifier)
//                    print("transactionid_\(transactionId) and productid_\(productId)")
//                    var childCount = ""
//                    if isMonthlySelected
//                    {
//                        childCount = arrSubsDataMonthly.first(where: {$0.productIdentifry == productId})?.childCount ?? ""
//                    }else {
//                        childCount = arrSubsDataYearly.first(where: {$0.productIdentifry == productId})?.childCount ?? ""
//                    }
//                   self.apiCallForSubscription(aTransactionID: transactionId, aChildCount: childCount, aBunddleID: productId)
//                    SKPaymentQueue.default().finishTransaction(transaction as! SKPaymentTransaction)
//                    appDelegate.hideHud()
//                    break
//                case .failed:
//                    appDelegate.hideHud()
////                    self.popupAlert(
////                        title: "Purchase Failed",
////                        message: "The in-app purchase could not be completed. Please try again.",
////                        actionTitles: ["OK"],
////                        actions: [{ action1 in
////                        }, nil]
////                    )
//                    if let error = trans.error as? SKError {
//                            print("Purchase error:", error.code, error.localizedDescription)
//                        }
//                    SKPaymentQueue.default().finishTransaction(transaction as! SKPaymentTransaction)
//                    break
//                case .restored:
//                    //Get data from backend and set user free..
//                    let transactionId = transaction.original?.transactionIdentifier ?? ""
//                    let productId = transaction.original?.payment.productIdentifier ?? transaction.payment.productIdentifier
//                    print("transactionid_\(transactionId) and productid_\(productId)")
//
//                    // send transactionId & productId to backend if needed
//                    SKPaymentQueue.default().finishTransaction(transaction as! SKPaymentTransaction)
//                    appDelegate.hideHud()
//                    break
//                default: break
//                }}}
//    }
//
//    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue)    {
//        for transact:SKPaymentTransaction in queue.transactions        {
//
//            if transact.transactionState == SKPaymentTransactionState.restored
//            {
//                SKPaymentQueue.default().finishTransaction(transact)
//            }
//            if transact.transactionState == SKPaymentTransactionState.purchased
//            {
//                SKPaymentQueue.default().finishTransaction(transact)
//            }
//        }
//    }
//
//    // MARK: - MAKE PURCHASE OF A PRODUCT
//    func canMakePurchases() -> Bool {
//        print(SKPaymentQueue.canMakePayments())
//        return SKPaymentQueue.canMakePayments()
//    }
//    func purchaseMyProduct(product: SKProduct) {
//
//        if self.canMakePurchases() {
//            print(SKPaymentQueue.canMakePayments())
//            print("PRODUCT TO PURCHASE: \(product.productIdentifier)")
//            self.productID = product.productIdentifier
//            let payment = SKPayment(product: product)
//            SKPaymentQueue.default().add(payment)
//            SKPaymentQueue.default().add(self)
//        } else {
//            appDelegate.hideHud()
//            //            self.view.makeToast("تم تعطيل المشتريات في جهازك!")
//            self.popupAlert(title: "", message: "Purchases have been disabled on your device!", actionTitles: ["OK"], actions:[{action1 in
//            }, nil])
//        }
//    }
//    func request(_ request: SKRequest, didFailWithError error: Error) {
//        print("app receipt refresh request did fail with error: \(error)")
//        // for some clues see here: https://samritchie.net/2015/01/29/the-operation-couldnt-be-completed-sserrordomain-error-100/
//    }
//
//    //MARK: - Set action on purchase product..
//    func setProductPurchase(strProductId : String)
//    {
//        isConnectedToNetwork1 { [self] isConnected in
//            if isConnected {
//                for productMain in iapProducts
//                {
//                    if productMain.productIdentifier == strProductId{
//                        purchaseMyProduct(product: productMain)
//                        return
//                    }
//                }
//            }
//        }
//    }
//}

//MARK: - Collectionview delegates and datasource...
extension SubscriptionListVC : UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {

        let spacing: CGFloat = 3
        let totalSpacing = spacing * 1 // 3 cells = 2 spaces
        let width = (collViewPlanList.bounds.width - totalSpacing) / 2

        return CGSize(width: floor(width), height: 165)
    }
    func collectionView(_ collectionView: UICollectionView,
                          layout collectionViewLayout: UICollectionViewLayout,
                          minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
          return 3
      }

      func collectionView(_ collectionView: UICollectionView,
                          layout collectionViewLayout: UICollectionViewLayout,
                          minimumLineSpacingForSectionAt section: Int) -> CGFloat {
          return 3
      }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if isMonthlySelected
        {
            return self.arrSubsDataMonthly.count
        }
        return self.arrSubsDataYearly.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
    {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CellForPlans", for: indexPath) as! CellForPlans
        cell.setupCellDataFromModelDataWith(dataModel:(self.isMonthlySelected) ? self.arrSubsDataMonthly[indexPath.row] : self.arrSubsDataYearly[indexPath.row],selectedIndex:self.selectedIndex,currentIndex:indexPath.row)
        return cell

    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        self.selectedIndex = indexPath.row
        self.collViewPlanList.reloadData()
    }
}

//MARK: - Api callings...
extension SubscriptionListVC
{
    //MARK: - Subscribed api...
    func apiCallForSubscription(aTransactionID:String,aChildCount:String,aBunddleID:String)
    {
        let childCountInt = Int(aChildCount) ?? 1
        let param = ["originalTransactionId":aTransactionID,"maxChild":childCountInt,"bundleId":"org.app.GaurdianDrive"] as [String : Any]
        
        print(param)
        
        apiCallViewModel.postApiCallWithDisctionaryResponse(aUrl: WebURL.subscriptionVerify, param:param) { (isSuccess, responseDict,statusCode)  in
            
            appDelegate.hideHud()
            
            if isSuccess
            {
                print(responseDict)
                
                let dict = responseDict as NSDictionary

                // ✅ Map to model
                let userSubscriptionData = UserSubscriptionResponseModel.init(dict: dict)
                appDelegate.maxChildLimit = userSubscriptionData.maxChild > 0 ? userSubscriptionData.maxChild : 1
                let status = getSubscriptionStatus(userSubscriptionData.expiresDateLocal)

                switch status {

                case .expired:
                    appDelegate.isPurchaseVIP = false
                    appDelegate.subscriptionExpireDate = "Subscription Expired"
                    self.popupAlert(
                        title: "Subscription not purchased",
                        message: "Please purchase the subscription to continue using the app.",
                        actionTitles: ["OK"],
                        actions: [{ _ in
                            // Optional: redirect to purchase screen
                        }, nil]
                    )

                case .active(let message):

                    appDelegate.subscriptionExpireDate = message
                    appDelegate.isPurchaseVIP = true
                    print("✅ Active:", message)
                    self.popupAlert(
                        title: "Subscription Successful",
                        message: "Your subscription has been activated successfully.",
                        actionTitles: ["OK"],
                        actions: [{ _ in
                            self.navigationController?.popViewController(animated: true)
                        }, nil]
                    )
                }
                //UI update
                self.selectedIndex = 99
                self.viewState.selectedIndex = 99
                self.collViewPlanList?.reloadData()
            }
        }
    }
}
import SwiftUI

struct PremiumSubscriptionView: View {
    @Binding var isMonthlySelected: Bool
    @Binding var selectedIndex: Int
    
    var arrSubsDataMonthly: [SubscriptionModel]
    var arrSubsDataYearly: [SubscriptionModel]
    
    var onBack: () -> Void
    var onRestoreTop: () -> Void
    var onPurchase: () -> Void
    var onRestoreBottom: () -> Void
    var onTerms: () -> Void
    var onPrivacy: () -> Void

    let appDarkBlue = Color(red: 17/255, green: 40/255, blue: 96/255) // approximate from image
    let appGreen = Color(red: 40/255, green: 167/255, blue: 69/255) // approximate from image
    let lightGray = Color(red: 245/255, green: 245/255, blue: 245/255)

    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.title2)
                        .foregroundColor(appDarkBlue)
                }
                Spacer()
//                Button(action: onRestoreTop) {
//                    Text("Restore Purchases")
//                        .font(.system(size: 16, weight: .semibold))
//                        .foregroundColor(appDarkBlue)
//                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Header Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GuardianDrive Premium")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(appDarkBlue)
                        
                        Text("Auto-Renewable Subscription")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(appDarkBlue)
                        
                        Text("Choose the plan that works best for your family.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                    
                    // Features List
                    VStack(alignment: .leading, spacing: 12) {
                        FeatureRow(icon: "ic_feature_add_child", text: "Add up to 4 children", color: appDarkBlue)
                        FeatureRow(icon: "ic_feature_shield", text: "Manage & protect your child", color: appDarkBlue)
                        FeatureRow(icon: "ic_feature_clock", text: "Active / Deactive child", color: appDarkBlue)
                        FeatureRow(icon: "ic_feature_edit", text: "Edit child information", color: appDarkBlue)
                        FeatureRow(icon: "ic_feature_location", text: "Track your children using location", color: appDarkBlue)
                        FeatureRow(icon: "ic_feature_apps", text: "Track device apps", color: appDarkBlue)
//                        FeatureRow(icon: "ic_feature_more", text: "Many others", color: appDarkBlue)
                    }
                    .padding(.horizontal)
                    
                    // Toggle Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose your plan:")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(appDarkBlue)
                            .padding(.horizontal)
                        
                        HStack(spacing: 0) {
                            Button(action: {
                                withAnimation {
                                    isMonthlySelected = true
                                    selectedIndex = 99
                                }
                            }) {
                                Text("Monthly")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(isMonthlySelected ? .white : appDarkBlue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(isMonthlySelected ? appDarkBlue : Color.white)
                                    .clipShape(CustomCorner(corners: [.topLeft, .bottomLeft], radius: 10))
                            }
                            
                            Button(action: {
                                withAnimation {
                                    isMonthlySelected = false
                                    selectedIndex = 99
                                }
                            }) {
                                Text("Yearly")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(!isMonthlySelected ? .white : appDarkBlue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(!isMonthlySelected ? appDarkBlue : Color.white)
                                    .clipShape(CustomCorner(corners: [.topRight, .bottomRight], radius: 10))
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(appDarkBlue, lineWidth: 1)
                        )
                        .padding(.horizontal)
                    }
                    
                    // Plans Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        let activePlans = isMonthlySelected ? arrSubsDataMonthly : arrSubsDataYearly
                        ForEach(Array(activePlans.enumerated()), id: \.element.productIdentifry) { index, plan in
                            PlanCard(
                                plan: plan,
                                isSelected: selectedIndex == index,
                                isBestValue: plan.name.lowercased().contains("family4"),
                                isMonthlyView: isMonthlySelected,
                                action: {
                                    selectedIndex = index
                                    onPurchase()
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Information Section
                    VStack(alignment: .leading, spacing: 16) {
                        InfoRow(icon: "arrow.triangle.2.circlepath", text: "Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
                        InfoRow(icon: "creditcard", text: "Payment will be charged to your Apple ID account at confirmation of purchase.")
                        InfoRow(icon: "gearshape", text: "Manage or cancel your subscription anytime from Settings -> Apple ID -> Subscriptions.")
                    }
                    .padding()
                    .background(lightGray)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    
                    // Restore Purchases Button (Bottom)
                    Button(action: onRestoreBottom) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Restore Purchases")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(appDarkBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(appDarkBlue, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    
                    // Terms & Privacy Links
                    Text("\(Image(systemName: "lock")) By subscribing, you agree to our [**Privacy Policy**](privacy://) | [**Terms of Use**](terms://)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .tint(appDarkBlue)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                        .environment(\.openURL, OpenURLAction { url in
                            if url.absoluteString == "privacy://" {
                                onPrivacy()
                                return .handled
                            } else if url.absoluteString == "terms://" {
                                onTerms()
                                return .handled
                            }
                            return .systemAction
                        })
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
    }
}

struct FeatureRow: View {
    var icon: String
    var text: String
    var color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(icon) // Using custom asset image instead of systemName
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
                .frame(width: 20, height: 20, alignment: .center)
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.black)
            Spacer()
        }
    }
}

struct InfoRow: View {
    var icon: String
    var text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.gray)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

struct PlanCard: View {
    var plan: SubscriptionModel
    var isSelected: Bool
    var isBestValue: Bool
    var isMonthlyView: Bool
    var action: () -> Void
    
    let appDarkBlue = Color(red: 17/255, green: 40/255, blue: 96/255)
    let appGreen = Color(red: 40/255, green: 167/255, blue: 69/255)
    
    var body: some View {
        let themeColor = isSelected ? appGreen : appDarkBlue
        let durationText = isMonthlyView ? "1 Month" : "1 Year"
        
        let mainPriceStr = plan.price.replacingOccurrences(of: " ", with: "")
        let subPriceStr = plan.yearly.isEmpty ? "" : plan.yearly.replacingOccurrences(of: " ", with: "")
        
        VStack(spacing: 0) {
            // Header
            Text(plan.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(themeColor)
            
            VStack(spacing: 8) {
                Text("\(plan.childCount) \((Int(plan.childCount) ?? 1) > 1 ? "Children" : "Child") Included")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.top, 8)
                
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .foregroundColor(themeColor)
                    Text(durationText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(themeColor)
                }
                
                HStack(alignment: .bottom, spacing: 2) {
                    Text(mainPriceStr)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                    Text(isMonthlyView ? "/month" : "/year")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .padding(.bottom, 3)
                }
                
                if isMonthlyView && !subPriceStr.isEmpty {
                    Text("or \(subPriceStr) /year")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                } else {
                    Text(" ")
                        .font(.system(size: 12))
                }
                
                Button(action: action) {
                    Text("Choose Plan")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(themeColor)
                        .cornerRadius(6)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .padding(.top, 4)
            }
            .background(Color.white)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? themeColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .cornerRadius(10)
//        .overlay(
//            Group {
//                if isBestValue {
//                    Text("BEST VALUE")
//                        .font(.system(size: 9, weight: .bold))
//                        .foregroundColor(.white)
//                        .padding(.horizontal, 6)
//                        .padding(.vertical, 3)
//                        .background(appGreen)
//                        .cornerRadius(4)
//                        .offset(x: 0, y: -10)
//                }
//            }
//            , alignment: .topTrailing
//        )
    }
}

struct CustomCorner: Shape {
    var corners: UIRectCorner
    var radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
