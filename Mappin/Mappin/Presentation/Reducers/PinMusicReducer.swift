//
//  PinMusicReducer.swift
//  Mappin
//
//  Created by changgyo seo on 2023/05/03.
//

import ComposableArchitecture

import CoreLocation
import MapKit
import SwiftUI

protocol PinMusic: ReducerProtocol {
    var addPinUseCase: AddPinUseCase { get }
    var getPinsUseCase: GetPinsUseCase { get }
}

struct PinMusicReducer: PinMusic {
    
    let addPinUseCase: AddPinUseCase
    let getPinsUseCase: GetPinsUseCase
    
    struct IdForDebounce: Hashable { }
    
    struct State: Equatable {
        
        var mapAction: MapView.Action = .none {
            didSet(newValue){
                print("@KIO PIN \(newValue)")
            }
        }
        
        var currentLocation: MKCoordinateRegion = MKCoordinateRegion()
        var pinsUsingMap: [Pin] = []
        var pinsUsingList: [Pin] = []
        var mapUserTrakingMode: MapUserTrackingMode = .follow
        var showingPinsView: [AnnotaitionPinView] = []
        var detailPin: Pin?
        var temporaryPinLocation: MKCoordinateRegion = MKCoordinateRegion()
        var category: PinsCategory?
        var lastAction: UniqueAction<Action>?
    }
    
    
    enum Action: Equatable {
        
        case act(MapView.Action)
        case actAndChange(MapView.Action)
        case loadPins(category: PinsCategory?, centerLatitude: Double, centerLongitude: Double, latitudeDelta: Double, longitudeDelta: Double)
        case mapPins([Pin])
        case listPins([Pin])
        case addPin(music: Music, latitude: Double, longitude: Double)
        case tapPin(CGPoint)
        case showPopUpAndCloseAfter
        case completeAddPin(Pin)
        case actTemporaryPinLocation(MKCoordinateRegion)
        case none
        case refreshPins
        case focusToPin(Pin)
        case setCategory(PinsCategory)
    }
    
    func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
        state.lastAction = .init(action)
        
        switch action {
        case .none:
            return .none
            
        case .act(let value):
            switch value {
            case .none:
                return .none
            case .responseUpdate(_):
                return .none
                
            case .requestUpdate(here: let here, latitudeDelta: let latitudeDelta, longitudeDelta: let longitudeDelta):
                let category = state.category
                return .run { action in
                    await action.send(.loadPins(
                        category: category,
                        centerLatitude: here.0,
                        centerLongitude: here.1,
                        latitudeDelta: latitudeDelta,
                        longitudeDelta: longitudeDelta
                    ))
                }
            case .requestCurrentShowingPinViews( let views ):
                state.showingPinsView = views
                return .none
            default:
                return .none
            }
            
        case .actAndChange(let value):
            
            state.mapAction = value
            switch value {
            case .none:
                return .none
            case .responseUpdate(_):
                return .none
                
            case .requestUpdate(here: let here, latitudeDelta: let latitudeDelta, longitudeDelta: let longitudeDelta):
                let category = state.category
                
                return .run { action in
                    await action.send(.loadPins(
                        category: category,
                        centerLatitude: here.0,
                        centerLongitude: here.1,
                        latitudeDelta: latitudeDelta,
                        longitudeDelta: longitudeDelta
                    ))
                }
            default:
                return .none
            }
            
        case let .loadPins(category, centerLatitude, centerLongitude, latitudeDelta, longitudeDelta):
            let center = (centerLatitude, centerLongitude)
            return .merge(
                .task {
                    let mapPins: [Pin]
                    if centerLatitude != 404 && centerLongitude != 404 {
                        mapPins = try await getPinsUseCase.excuteUsingMap(
                            category: category,
                            center: center,
                            latitudeDelta: latitudeDelta,
                            longitudeDelta: longitudeDelta
                        )
                    }
                    else {
                        mapPins = try await getPinsUseCase.excuteUsingMap(
                            category: category,
                            center: center,
                            latitudeDelta: latitudeDelta,
                            longitudeDelta: longitudeDelta
                        )
                    }
                    return .mapPins(mapPins)
                },
                .task {
                    let listPins: [Pin]
                    if centerLatitude != 404 && centerLongitude != 404 {
                        listPins = try await getPinsUseCase.excuteUsingList(
                            category: category,
                            center: center,
                            latitudeDelta: latitudeDelta,
                            longitudeDelta: longitudeDelta
                        )
                    }
                    else {
                        listPins = try await getPinsUseCase.excuteUsingList(
                            category: category,
                            center: center,
                            latitudeDelta: latitudeDelta,
                            longitudeDelta: longitudeDelta
                        )
                    }
                    return .listPins(listPins)
                }
            )
            
            
        case .addPin(let music, let latitude, let longitude):
            return .run { action in
                let pin = try await addPinUseCase.excute(music: music, latitude: latitude, longitude: longitude)
                print("@KIO addpinReducer \(pin)")
                await action.send(.completeAddPin(pin))
                
                //        case let .addPin(music, latitudeDelta, longitudeDelta):
                //            let category = state.category
                //            return .task {
                //                try await addPinUseCase.excute(music: music)
                //                return .loadPins(
                //                    category: category,
                //                    centerLatitude: 404,
                //                    centerLongitude: 404,
                //                    latitudeDelta: latitudeDelta,
                //                    longitudeDelta: longitudeDelta
                //                )
                
            }
            
        case .mapPins(let pins):
            state.pinsUsingMap = pins
            state.mapAction = .responseUpdate(pins)
            return .none
            
        case .completeAddPin(let pin):
            state.detailPin = pin
            state.mapAction = .completeAdd(pin)
            return .none
            
        case .listPins(let pins):
            state.pinsUsingList = pins
            return .none
            
        case .tapPin( let point ):
            var returnPin: Pin?
            
            for view in state.showingPinsView {
                if view.frame.minX != 0.0 {
                    if view.frame.minX <= point.x
                        && point.x <= view.frame.minX + 40
                        && view.frame.minY - 40 <= point.y
                        && point.y <= view.frame.minY {
                        
                        returnPin = view.pin
                    }
                }
            }
            state.detailPin = returnPin
            guard let returnPin = returnPin else  {
                return .none
            }
            return .run { action in
                await action.send(
                    .actAndChange(
                        .setCenter(here:
                                    (returnPin.location.latitude,
                                     returnPin.location.longitude
                                    )
                                  )
                    )
                )
            }
        case .showPopUpAndCloseAfter:
            
            state.mapAction = .removePin()
            state.detailPin = nil
            state.mapAction = .setCenter(here: (RequestLocationRepository.manager.latitude, RequestLocationRepository.manager.longitude))
            return .none
            
        case .actTemporaryPinLocation(let here):
            state.temporaryPinLocation = here
            return .none
            
        case .refreshPins:
            print("@BYO action.refreshPins")
            return .none
            
        case let .focusToPin(pin):
            print("@BYO action.focusToPin \(pin)")
            let here = (pin.location.latitude, pin.location.longitude)
            return .send(.actAndChange(.setCenter(here: here)))
            
        case let .setCategory(category):
            state.category = category
            return .none
        }
    }
}

extension PinMusicReducer {
    static func build() -> Self {
        PinMusicReducer(
            addPinUseCase: DefaultMockDIContainer.shared.container.resolver.resolve(AddPinUseCase.self),
            getPinsUseCase: DefaultMockDIContainer.shared.container.resolver.resolve(GetPinsUseCase.self)
        )
    }
}

