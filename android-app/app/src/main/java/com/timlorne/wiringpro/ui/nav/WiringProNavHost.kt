package com.timlorne.wiringpro.ui.nav

import androidx.compose.runtime.Composable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.timlorne.wiringpro.data.repository.WiringRepository
import com.timlorne.wiringpro.ui.screens.connectorlist.ConnectorListScreen
import com.timlorne.wiringpro.ui.screens.connectorlist.ConnectorListViewModel
import com.timlorne.wiringpro.ui.screens.editor.PinGridEditorScreen
import com.timlorne.wiringpro.ui.screens.editor.PinGridEditorViewModel
import com.timlorne.wiringpro.ui.screens.loom.LoomCanvasScreen
import com.timlorne.wiringpro.ui.screens.loom.LoomCanvasViewModel
import com.timlorne.wiringpro.ui.screens.newconnector.NewConnectorScreen
import com.timlorne.wiringpro.ui.screens.newconnector.NewConnectorViewModel
import com.timlorne.wiringpro.ui.screens.projectlist.ProjectListScreen
import com.timlorne.wiringpro.ui.screens.projectlist.ProjectListViewModel

private class SimpleFactory(private val create: () -> ViewModel) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = create() as T
}

/**
 * Route shape: project_list -> connector_list/{projectId} -> one of
 * new_connector/{projectId}, editor/{projectId}/{connectorId}, or
 * loom/{projectId} (the whole-loom canvas — every connector on one
 * pan/zoomable surface).
 */
@Composable
fun WiringProNavHost(repository: WiringRepository) {
    val navController: NavHostController = rememberNavController()

    NavHost(navController = navController, startDestination = "project_list") {
        composable("project_list") {
            val vm: ProjectListViewModel = viewModel(
                factory = SimpleFactory { ProjectListViewModel(repository) }
            )
            ProjectListScreen(
                viewModel = vm,
                onOpenProject = { projectId -> navController.navigate("connector_list/$projectId") }
            )
        }

        composable(
            route = "connector_list/{projectId}",
            arguments = listOf(navArgument("projectId") { type = NavType.StringType })
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId")!!
            val vm: ConnectorListViewModel = viewModel(
                factory = SimpleFactory { ConnectorListViewModel(repository, projectId) }
            )
            ConnectorListScreen(
                viewModel = vm,
                onBack = { navController.popBackStack() },
                onAddConnector = { navController.navigate("new_connector/$projectId") },
                onOpenConnector = { connectorId -> navController.navigate("editor/$projectId/$connectorId") },
                onViewLoom = { navController.navigate("loom/$projectId") }
            )
        }

        composable(
            route = "new_connector/{projectId}",
            arguments = listOf(navArgument("projectId") { type = NavType.StringType })
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId")!!
            val vm: NewConnectorViewModel = viewModel(
                factory = SimpleFactory { NewConnectorViewModel(repository, projectId) }
            )
            NewConnectorScreen(
                viewModel = vm,
                onConnectorCreated = { connectorId ->
                    navController.navigate("editor/$projectId/$connectorId") {
                        popUpTo("connector_list/$projectId")
                    }
                },
                onBack = { navController.popBackStack() }
            )
        }

        composable(
            route = "editor/{projectId}/{connectorId}",
            arguments = listOf(
                navArgument("projectId") { type = NavType.StringType },
                navArgument("connectorId") { type = NavType.StringType }
            )
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId")!!
            val connectorId = backStackEntry.arguments?.getString("connectorId")!!
            val vm: PinGridEditorViewModel = viewModel(
                factory = SimpleFactory { PinGridEditorViewModel(repository, projectId, connectorId) }
            )
            PinGridEditorScreen(viewModel = vm, onBack = { navController.popBackStack() })
        }

        composable(
            route = "loom/{projectId}",
            arguments = listOf(navArgument("projectId") { type = NavType.StringType })
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId")!!
            val vm: LoomCanvasViewModel = viewModel(
                factory = SimpleFactory { LoomCanvasViewModel(repository, projectId) }
            )
            LoomCanvasScreen(viewModel = vm, onBack = { navController.popBackStack() })
        }
    }
}

